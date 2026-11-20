#!/usr/bin/env python3
"""PreToolUse 가드 — 비밀값 출력과 되돌릴 수 없는 명령을 막는다 (v2, 2026-10-12).

bypass(--dangerously-skip-permissions) 모드에서도 PreToolUse 훅의 deny 는 먹힌다.
CLAUDE.md 의 부탁이 아니라 결정론으로 막을 것만 둔다. 정당한 사용(`. ./.env` 로 불러 쓰기, 키 이름만 보기,
존재 확인)은 통과시키고, 막을 때는 대안을 이유에 적어 Claude 가 바로 우회로를 찾게 한다.

구조: 명령 문자열을 따옴표·$( )·heredoc 을 인식해 '단순명령'으로 나누고(파이프라인 묶음 유지),
단순명령마다 첫 단어로 판정한다. 정규식으로 줄 전체를 훑지 않는다 — v1 은 따옴표 안 `|` 를 경계로 읽어
유출을 놓치고(grep -E "A|B" .env) 문서 문장을 명령으로 오인했다(세션 기록 15,237건 대조, 오탐 57%).

입력: stdin JSON {tool_name, tool_input, cwd}. 출력: deny 일 때만 hookSpecificOutput JSON.
어떤 오류든 통과(exit 0) — 가드가 하네스를 멈추게 하지 않는다.
테스트: test_guard.py (같은 폴더).
"""
import json
import os
import re
import shlex
import sys

HOME = os.path.expanduser("~")

# ---------------------------------------------------------------- 비밀 파일
ENV_NAME = re.compile(r"^\.env(\.[\w.-]+)?$")
SAFE_ENV = re.compile(r"^\.env\.(example|sample|template|dist|defaults?)$")
SECRET_ABS = {
    os.path.join(HOME, ".claude/.credentials.json"),
    os.path.join(HOME, ".zshenv.local"),
    os.path.join(HOME, ".pgpass"),
    os.path.join(HOME, ".netrc"),
}
SSH_DIR = os.path.join(HOME, ".ssh")
SECRET_BASENAMES = {".credentials.json", ".zshenv.local", ".pgpass", ".netrc"}


def is_secret_path(p, cwd=""):
    if not p or not isinstance(p, str):
        return False
    p = os.path.expanduser(os.path.expandvars(p))
    base = os.path.basename(p.rstrip("/"))
    if SAFE_ENV.match(base):
        return False
    if ENV_NAME.match(base) or base in SECRET_BASENAMES:
        return True
    ap = os.path.normpath(os.path.join(cwd or "/", p)) if not os.path.isabs(p) else os.path.normpath(p)
    if ap in SECRET_ABS or re.match(r"^/proc/[^/]+/environ$", ap):
        return True
    if ap.startswith(SSH_DIR + "/"):
        b = os.path.basename(ap)
        return not (b.endswith(".pub") or b.startswith("known_hosts") or b.startswith("authorized_keys")
                    or b.startswith("config") or b == "environment")
    return bool(re.match(r"^id_(rsa|ed25519|ecdsa|dsa)$", base))


SECRET_VAR = re.compile(r"[A-Z0-9_]*(DB|DSN|URL|KEY|TOKEN|SECRET|PASS|PASSWORD|PASSWD|PW|PAT|CREDENTIALS?|AUTH)\b[A-Z0-9_]*")
# 이름에 DB 가 들어가도 DB '이름'·호스트·포트·사용자는 비밀이 아니다(코퍼스 오탐: TIMESCALE_DB 등)
NONSECRET_VAR = re.compile(r"^(?:[A-Z0-9_]*_(?:HOST|PORT|USER|USERNAME|NAME|DIR|PATH|CONTAINER)|TIMESCALE_DB|POSTGRES_DB|PGDATABASE|PG_DB)$")


def is_secret_var(name):
    return bool(SECRET_VAR.fullmatch(name)) and not NONSECRET_VAR.match(name)

# ---------------------------------------------------------------- 셸 분해
def blank_quotes(s):
    """따옴표 안 글자를 공백으로(위치 보존). $( ) 안의 따옴표도 처리."""
    out = list(s)
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            out[i + 1] = " "
            i += 2
            continue
        if c in ("'", '"'):
            j = i + 1
            while j < n and s[j] != c:
                if c == '"' and s[j] == "\\" and j + 1 < n:
                    out[j] = out[j + 1] = " "
                    j += 2
                    continue
                out[j] = " "
                j += 1
            i = j + 1
            continue
        i += 1
    return "".join(out)


HEREDOC = re.compile(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
SHELL_INTERP = {"bash", "sh", "zsh", "ssh", "dash"}
SQL_INTERP = {"psql", "sqlite3", "mysql"}


def split_heredocs(cmd):
    """heredoc 본문을 떼어 낸다. 돌려주는 값: (본문 뺀 명령, [(해석기 종류, 본문)])."""
    lines = cmd.split("\n")
    keep, bodies = [], []
    i = 0
    while i < len(lines):
        line = lines[i]
        keep.append(line)
        i += 1
        b = blank_quotes(line)
        m = HEREDOC.search(b) or HEREDOC.search(line)
        if not m:
            continue
        dash, term = m.group(1), m.group(3)
        # heredoc 이 속한 단순명령의 첫 단어로 해석기 판정
        seg = re.split(r"&&|\|\||[;|]", b[: m.start()])[-1]
        words = seg.split()
        first = next((w for w in words if not re.match(r"^\w+=", w) and w not in ("sudo", "time", "nohup", "exec")), "")
        if first == "docker" and any(w in SQL_INTERP for w in words):
            first = "psql"
        kind = "shell" if os.path.basename(first) in SHELL_INTERP else ("sql" if os.path.basename(first) in SQL_INTERP else "doc")
        body = []
        while i < len(lines):
            l2 = lines[i]
            i += 1
            if (l2.lstrip("\t") if dash else l2) == term:
                keep.append(l2)
                break
            body.append(l2)
        bodies.append((kind, "\n".join(body)))
    return "\n".join(keep), bodies


def split_commands(cmd):
    """따옴표 밖 ; & && || 줄바꿈 으로 파이프라인을, | 로 단순명령을 나눈다.
    돌려주는 값: [[단순명령 원문, ...] 파이프라인, ...]. $( ) <( ) 안은 별도 명령으로 펼친다."""
    b = blank_quotes(cmd)
    pipelines, cur_pipe, start = [], [], 0
    i, n = 0, len(b)
    stack = []
    while i < n:
        c = b[i]
        if b.startswith("$(", i) or b.startswith("<(", i) or b.startswith(">(", i):
            stack.append(i)
            i += 2
            continue
        if c == "(" and stack:
            stack.append(-1)
        if c == ")" and stack:
            stack.pop()
            i += 1
            continue
        if not stack:
            if b.startswith("&&", i) or b.startswith("||", i):
                cur_pipe.append(cmd[start:i])
                pipelines.append(cur_pipe)
                cur_pipe = []
                i += 2
                start = i
                continue
            if c in ";\n()" or (c == "&" and not b.startswith("&>", i) and (i == 0 or b[i - 1] not in "<>")):
                cur_pipe.append(cmd[start:i])
                pipelines.append(cur_pipe)
                cur_pipe = []
                i += 1
                start = i
                continue
            if c == "|" and not b.startswith("||", i) and (i == 0 or b[i - 1] != ">"):
                cur_pipe.append(cmd[start:i])
                i += 1
                start = i
                continue
        i += 1
    cur_pipe.append(cmd[start:])
    pipelines.append(cur_pipe)
    out = [[s for s in p if s.strip()] for p in pipelines]
    out = [p for p in out if p]
    # 치환 안의 명령: (앞 맥락, 안쪽 문자열). 큰따옴표 안 $( ) 와 `...` 도 산다(작은따옴표 안만 죽는다).
    inner = []
    for s0, _end, body in find_substs(cmd):
        inner.append((blank_quotes(cmd[:s0]).rstrip().rstrip('"'), body))
    return out, inner


def find_substs(cmd):
    """바깥쪽 $( ) <( ) >( ) `...` 의 (시작, 끝, 안쪽). 작은따옴표 안은 무시, 큰따옴표 안은 본다."""
    res, i, n, dq = [], 0, len(cmd), False
    while i < n:
        c = cmd[i]
        if c == "\\":
            i += 2
            continue
        if c == "'" and not dq:
            j = cmd.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        if c == '"':
            dq = not dq
        elif c == "`":
            j = cmd.find("`", i + 1)
            if j < 0:
                break
            res.append((i, j, cmd[i + 1:j]))
            i = j + 1
            continue
        elif cmd.startswith("$(", i) or (not dq and (cmd.startswith("<(", i) or cmd.startswith(">(", i))):
            depth, j, q = 1, i + 2, None
            while j < n and depth:
                d = cmd[j]
                if q:
                    if d == q:
                        q = None
                    elif d == "\\" and q == '"':
                        j += 1
                elif d in "'\"":
                    q = d
                elif d == "\\":
                    j += 1
                elif d == "(":
                    depth += 1
                elif d == ")":
                    depth -= 1
                j += 1
            res.append((i, j - 1, cmd[i + 2:j - 1]))
            i = j
            continue
        i += 1
    return res


REDIR = re.compile(r"^(\d*|&)(>>?|<<?<?|>&|<&)(&?\d+|-)?$")
REDIR_GLUED = re.compile(r"^(\d*|&)(>>?|<|>&|<&)\S+$")


def words_of(seg):
    """shlex 단어. 리다이렉트(2>/dev/null, > f, 2>&1, < f)는 뺀다 — 인자가 아니다. `< 파일` 은 secret_reason 이 따로 본다."""
    try:
        w = shlex.split(seg, comments=False)
    except ValueError:
        w = seg.split()
    out, skip = [], False
    for t in w:
        if skip:
            skip = False
            continue
        if REDIR.match(t):
            skip = not re.search(r"&\d+$|&-$", t)
            continue
        if REDIR_GLUED.match(t):
            continue
        out.append(t)
    return out


RESERVED = {"{", "}", "!", "then", "do", "else", "elif", "if", "while", "until"}
WRAPPERS = {"sudo", "time", "nohup", "exec", "command", "builtin", "nice", "ionice", "stdbuf", "timeout", "xargs", "env"}


def head_index(w):
    """환경변수 대입·래퍼를 건너뛴 실제 명령 위치."""
    i = 0
    while i < len(w):
        t = w[i]
        if t in RESERVED:
            i += 1
            continue
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
            continue
        if t in WRAPPERS and i + 1 < len(w):
            if t == "env" and not any(re.match(r"^[A-Za-z_]\w*=", x) or x.startswith("-") for x in w[i + 1:i + 2]):
                # `env cmd` 는 래퍼, 맨 `env` 는 덤프(아래에서 판정)
                pass
            i += 1
            while i < len(w) and w[i].startswith("-") and w[i - 1] in ("timeout", "nice", "ionice", "stdbuf", "sudo", "xargs"):
                i += 1
            if w[i - 1] == "timeout" and i < len(w) and re.match(r"^\d", w[i]):
                i += 1
            continue
        return i
    return len(w)


# ---------------------------------------------------------------- 판정: 비밀
READERS = {"cat", "bat", "batcat", "less", "more", "head", "tail", "nl", "tac", "strings", "xxd", "od", "hexdump",
           "base64", "sed", "awk", "gawk", "grep", "egrep", "fgrep", "rg", "cut", "sort", "uniq", "diff", "jq", "paste",
           "fold", "column", "tee", "vi", "vim", "nvim", "nano", "code", "python", "python3", "perl", "ruby", "node",
           "dd", "iconv", "envsubst", "dotenv"}
SENDERS = {"curl", "wget", "scp", "rsync", "nc", "ncat", "socat", "sftp"}
SILENT = {".", "source", "test", "[", "[[", "ls", "stat", "wc", "file", "mv", "cp", "ln", "chmod", "chown", "touch",
          "rm", "git", "echo", "printf", "true", ":", "realpath", "readlink", "du", "md5sum", "sha256sum", "cmp"}
MASK_TAIL = re.compile(r"^\s*(cut\b.*-f\s*1(?![,\d-])|sed\s+(-E\s+)?['\"]s/=\.\*/[^/]{0,16}/[gI]*['\"]\s*$|wc\b|"
                       r"grep\s+-[a-zA-Z]*[cqlL]|awk\s+-F\s*['\"]?=['\"]?\s+['\"]\{\s*print\s+\$1\s*\}['\"])")


def mask_tail(seg):
    """파이프 뒤쪽이 값을 가리는 필터인가(키 이름·개수만 남김)."""
    if MASK_TAIL.match(seg):
        return True
    w = words_of(seg)
    if w and os.path.basename(w[0]) in ("grep", "rg", "egrep") and any(re.match(r"^-[a-zA-Z]*o", a) for a in w[1:]):
        pat = next((a for a in w[1:] if not a.startswith("-")), "")
        return pat.startswith("^") and ".*" not in pat and ".+" not in pat and "\\S" not in pat
    return False


def grep_pattern(args):
    for j, a in enumerate(args):
        if a in ("-e", "--regexp") and j + 1 < len(args):
            return args[j + 1]
    return next((a for a in args if not a.startswith("-")), "")


def nonsecret_keys_only(args):
    """grep 패턴이 비밀처럼 보이지 않는 키 이름들만 고르는가(예: '^(TIMESCALE_HOST|BACKUP_DIR)=')."""
    if any(re.match(r"^-[a-zA-Z]*v", a) for a in args if a.startswith("-") and not a.startswith("--")):
        return False
    pat = grep_pattern(args)
    if not pat or re.search(r"\.[*+]|\[|\\S|\\w|\$\{?[A-Za-z]", pat):
        return False
    names = re.findall(r"[A-Za-z][A-Za-z0-9_]*", pat)
    if not names or re.sub(r"[A-Za-z0-9_^()|\\=]", "", pat):
        return False  # 이름·^·(|)·= 말고 다른 정규식 문자가 있으면 임의 키가 걸릴 수 있다
    anchored = bool(re.match(r"^\(?\^", pat)) and all(p2.lstrip("(").startswith("^") or not p2 for p2 in re.split(r"\\?\|", pat.strip("()")) if p2) or pat.startswith("^(")
    icase = any(re.match(r"^-[a-zA-Z]*i", a) for a in args if a.startswith("-") and not a.startswith("--"))
    if not anchored and (icase or not all(re.fullmatch(r"[A-Z][A-Z0-9]*_[A-Z0-9_]+", n) and len(n) >= 6 for n in names)):
        return False  # 앵커 없는 짧은·소문자 패턴은 값 안(예: DSN 의 localhost)에서도 걸린다
    return not any(SECRET_VAR.search(n.upper()) and not NONSECRET_VAR.match(n.upper()) for n in names)


DSN_MASK = re.compile(r"^\s*sed\b.*\[\^:?@?\]\s*[*+]\s*@|^\s*sed\b.*\[\^@\][*+]@")


def dsn_masked(w, h, tail):
    """`grep '^APP_DB' .env | sed 's/:[^:@]*@/:***@/'` — 이름으로 고른 DSN 줄의 비밀번호를 가린다."""
    if h >= len(w) or os.path.basename(w[h]) not in ("grep", "rg", "egrep") or not any(DSN_MASK.search(t) for t in tail):
        return False
    if any(re.match(r"^-[a-zA-Z]*v", a) for a in w[h + 1:] if a.startswith("-") and not a.startswith("--")):
        return False
    pat = re.sub(r"=(\.\*)?$", "", grep_pattern(w[h + 1:]))
    return bool(re.fullmatch(r"\^[A-Z][A-Z0-9_]*|\^?\((\^?[A-Z][A-Z0-9_]*\|)*\^?[A-Z][A-Z0-9_]*\)", pat))


def keys_only(w, h):
    """단독으로 값이 아니라 키 이름·개수만 내는 형태."""
    cmd = os.path.basename(w[h]) if h < len(w) else ""
    args = w[h + 1:]
    joined = " ".join(args)
    if cmd in ("grep", "rg", "egrep") and any(re.match(r"^-[a-zA-Z]*o", a) for a in args if a.startswith("-")):
        pat = grep_pattern(args)
        if pat.startswith("^") and not re.search(r"=|\.[*+]|\[\^", pat):
            return True
    if cmd in ("grep", "rg", "egrep") and nonsecret_keys_only(args):
        return True
    if cmd in ("grep", "rg", "egrep") and any(re.match(r"^-[a-zA-Z]*[qcl]", a) for a in args if a.startswith("-") and not a.startswith("--")):
        return True
    if cmd in ("grep", "rg", "egrep") and any(re.match(r"^-[a-zA-Z]*o", a) for a in args) and re.search(r"=['\"]?\s|\^\[A-Z_", joined + " ") \
            and not re.search(r"\.[*+]|\[\^|\\S", grep_pattern(args)):
        return True
    if cmd == "cut" and re.search(r"-f\s*1(?![,\d-])", joined) and re.search(r"-d\s*['\"]?=", joined):
        return True
    if cmd == "sed" and re.search(r"s/=\.\*/[^/]{0,16}/", joined):
        return True
    if cmd in ("awk", "gawk") and re.search(r"-F\s*['\"]?=", joined) and re.search(r"print\s+\$1\s*\}", joined):
        return True
    return False


def secret_tokens(w, cwd):
    toks = []
    for i, t in enumerate(w):
        cand = t
        if t.startswith("<") and len(t) > 1:
            cand = t[1:]
        cand = cand.split("=", 1)[1] if "=" in cand else cand
        cand = cand.lstrip("@")
        if is_secret_path(cand, cwd):
            toks.append((i, cand))
    return toks


def secret_reason(pipe, cwd, ctx_load=False):
    """파이프라인(단순명령 목록) 하나에서 비밀 파일 내용이 밖으로 나오면 토큰을 돌려준다."""
    for k, seg in enumerate(pipe):
        w = words_of(seg)
        if not w:
            continue
        h = head_index(w)
        toks = secret_tokens(w, cwd)
        redirect_in = re.search(r"(^|\s)<\s*(\S+)", blank_quotes(seg))
        if redirect_in:
            tgt = seg[redirect_in.start(2):redirect_in.end(2)].strip("'\"")
            if is_secret_path(tgt, cwd):
                toks.append((-1, tgt))
        if not toks:
            continue
        cmd = os.path.basename(w[h]) if h < len(w) else ""
        if cmd in SENDERS:
            return toks[0][1]
        if cmd in (".", "source") or ctx_load:
            continue
        if keys_only(w, h) or dsn_masked(w, h, pipe[k + 1:]):
            continue
        tail = pipe[k + 1:]
        if tail and any(mask_tail(t) for t in tail):
            continue
        if any(re.search(r"(^|\s)xargs(\s+-\S+)*\s+(" + "|".join(READERS) + r")\b", t) for t in tail) or \
                (cmd == "find" and re.search(r"-exec\s+(" + "|".join(READERS) + r")\b", seg)):
            return toks[0][1]
        if cmd in SILENT and toks[0][0] != -1:
            continue
        if cmd in READERS or toks[0][0] == -1:
            return toks[0][1]
        if cmd in ("while", "read", "mapfile", "readarray"):
            return toks[0][1]
    return None


def strip_subst(s):
    """$( ... ) 를 지운다(따옴표 안 괄호 무시) — `echo "set: $([ -n "$DB" ] && echo yes)"` 는 값 출력이 아니다."""
    b = re.sub(r"'[^']*'", lambda m: " " * len(m.group(0)), s)  # 큰따옴표 안 $( ) 는 살아 있다
    out, i, depth, start = [], 0, 0, 0
    while i < len(b):
        if b.startswith("$(", i):
            if depth == 0:
                out.append(s[start:i])
            depth += 1
            i += 2
            continue
        if b[i] == ")" and depth:
            depth -= 1
            if depth == 0:
                start = i + 1
        i += 1
    if depth == 0:
        out.append(s[start:])
    return "".join(out)


def env_dump_reason(pipe):
    """환경변수(불러 쓴 비밀 포함)를 통째로 또는 이름으로 출력."""
    for k, seg in enumerate(pipe):
        w = words_of(seg)
        if not w:
            continue
        h = head_index(w)
        # `env` 단독(래퍼 아님) — head_index 가 env 를 건너뛰면 끝에 도달
        bare = w[h - 1:] if (h >= 1 and w[h - 1] == "env" and h >= len(w)) else w[h:]
        if h >= len(w) and w and w[-1] == "env":
            bare = ["env"]
        tail_masked = any(mask_tail(t) for t in pipe[k + 1:])
        if bare in (["env"], ["printenv"], ["set"], ["export", "-p"], ["export"], ["declare", "-x"], ["declare", "-p"], ["typeset", "-x"]):
            if not tail_masked:
                return "env"
            continue
        if h >= len(w):
            continue
        cmd = os.path.basename(w[h])
        if cmd == "printenv" and any(is_secret_var(a) for a in w[h + 1:]):
            return "printenv"
        if cmd == "set" and (any(re.match(r"^-[a-zA-Z]*x", a) for a in w[h + 1:]) or w[h + 1:h + 3] == ["-o", "xtrace"]):
            return "set -x"
        if cmd in ("declare", "typeset") and any(is_secret_var(a) for a in w[h + 1:] if not a.startswith("-")):
            return "declare -p"
        if cmd == "docker" and "exec" in w[h + 1:h + 2]:
            j = h + 2
            while j < len(w) and w[j].startswith("-"):
                j += 2 if w[j] in ("-e", "--env", "-u", "--user", "-w", "--workdir", "--env-file") else 1
            inner = w[j + 1:]
            if (inner == ["env"] or inner == ["printenv"] or (inner[:1] == ["printenv"] and any(is_secret_var(a) for a in inner[1:]))):
                if not tail_masked:
                    return "docker exec env"
        if cmd in ("echo", "printf"):
            raw = strip_subst(seg)
            for m in re.finditer(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)([^}]*)\}?", raw):
                name, rest = m.group(1), m.group(2) or ""
                if not is_secret_var(name):
                    continue
                if raw[m.start():m.start() + 3] == "${#":
                    continue
                if re.match(r"^:?\+", rest) or rest in ("%%:*", "%:*", "#*@", "##*@"):  # 스킴만·호스트 뒤만
                    continue
                if tail_masked:
                    continue
                return "$" + name
    return None


# ---------------------------------------------------------------- 판정: 되돌릴 수 없는 명령
PROTECTED_RM = {"/", "/*", "~", "~/", "~/*", "$HOME", "${HOME}", "$HOME/", "$HOME/*", HOME, HOME + "/", HOME + "/*",
                "~/git", "~/git/", "~/git/*", "$HOME/git", "$HOME/git/", HOME + "/git", HOME + "/git/", HOME + "/git/*",
                ".", "./", "..", "../", "*", "./*", "/home", "/home/"}


def danger_reason(seg, cwd):
    w = words_of(seg)
    if not w:
        return None
    h = head_index(w)
    if h >= len(w):
        return None
    cmd = os.path.basename(w[h])
    args = w[h + 1:]
    flags = [a for a in args if a.startswith("-")]
    pos = [a for a in args if not a.startswith("-")]

    if cmd == "rm":
        rec = any(a in ("-r", "-R", "--recursive") or re.match(r"^-[a-zA-Z]*[rR]", a) for a in flags)
        if rec:
            prot = {"/", "/home", HOME, os.path.join(HOME, "git"), os.path.normpath(cwd or "/")}
            for a in pos:
                x = re.sub(r"\$\{?HOME\}?", HOME, os.path.expanduser(a))
                x = re.sub(r"(/\*?)+/?$|/\.$", "", x) or "/"
                if a in PROTECTED_RM or os.path.normpath(os.path.join(cwd or "/", x)) in prot \
                        or a.rstrip("/").endswith("/.git") or a.rstrip("/") == ".git":
                    return "Recursive delete of home, root, ~/git, the current directory or .git as a whole. Name the specific subpath to delete (for worktrees use `git worktree remove`)."

    if cmd == "git":
        i = h + 1
        while i < len(w) and w[i].startswith("-"):
            i += 2 if w[i] in ("-C", "-c", "--git-dir", "--work-tree") else 1
        sub = w[i] if i < len(w) else ""
        rest = w[i + 1:]
        if sub == "push":
            for a in rest:
                if a == "--force" or a == "--mirror" or (re.match(r"^-[a-zA-Z]+$", a) and "f" in a) or (a.startswith("+") and len(a) > 1):
                    return "Force push (overwrites remote history). Use `--force-with-lease`, and ask the user first if the branch is shared."
        if sub == "stash":
            op = rest[0] if rest else ""
            if op in ("", "pop", "clear", "save") or (op == "drop" and len(rest) == 1) or (op == "push" and "-m" not in rest and "--message" not in rest) or (op.startswith("-") and op not in ("-h", "--help")):
                return "The stash stack is shared by all worktrees and sessions. Use a temporary WIP commit, or `git stash push -u -m <tag>` then `git stash apply <sha>` by SHA (no pop, clear or bare drop)."

    if cmd == "crontab":
        if any(re.match(r"^-[a-z]*r", a) for a in flags):
            return "Deletes the whole crontab. To change it, edit the repo's deploy/crontab.<host> and use the cron-install flow."
        p2 = [a for j, a in enumerate(args) if not a.startswith("-") and not (j > 0 and args[j - 1] == "-u")]
        if "-" in args or p2:
            return "Overwrites the whole crontab (wipes every repo's managed block). Edit the repo's deploy/crontab.<host> and run `cron-install`."

    if cmd == "find" and ("-delete" in args or any(a2 in ("rm", "/bin/rm") for a2 in args)):
        start = pos[0] if pos else "."
        x = os.path.normpath(os.path.join(cwd or "/", re.sub(r"\$\{?HOME\}?", HOME, os.path.expanduser(start))))
        if x in {"/", "/home", HOME, os.path.join(HOME, "git"), os.path.normpath(cwd or "/")}:
            return "find -delete over all of home, root, ~/git or the current directory. Narrow the start path to the subdirectory to delete."
    if cmd in ("docker", "docker-compose"):
        a = w[h:]
        if "rm" in a and ("compose" in a or cmd == "docker-compose") and any(x in ("-v", "--volumes") or re.match(r"^-[a-zA-Z]*v[a-zA-Z]*$", x) for x in a):
            return "Docker volume deletion: a database volume holds all of its data and has no second copy."
        if ("down" in a and ("compose" in a or cmd == "docker-compose")
                and any(x in ("-v", "--volumes") or re.match(r"^-[a-zA-Z]*v[a-zA-Z]*$", x) for x in a)):
            return "Docker volume deletion: a database volume holds all of its data and has no second copy."
        if a[1:3] == ["volume", "rm"] or a[1:3] == ["volume", "prune"] or (a[1:3] == ["system", "prune"] and "--volumes" in a):
            return "Docker volume deletion: a database volume holds all of its data and has no second copy."

    if cmd in ("reboot", "poweroff", "halt", "shutdown") or (cmd == "systemctl" and pos[:1] and pos[0] in ("reboot", "poweroff", "halt", "kexec")):
        return "Host reboot/power-off: stops every cron job, daemon and session running on this host."

    if cmd in ("mkfs", "wipefs") or cmd.startswith("mkfs.") or (cmd == "dd" and any(a.startswith("of=/dev/") for a in args)):
        return "Disk format/overwrite."

    if cmd in SQL_INTERP or (cmd == "docker" and any(x in SQL_INTERP for x in w)):
        if sql_danger(seg):
            return SQL_MSG
    return None


SQL_MSG = "Dropping or emptying DB objects is irreversible. Write it as a migration file and get user approval."
SQL_DROP = re.compile(r"\b(DROP\s+(TABLE|SCHEMA|DATABASE|MATERIALIZED\s+VIEW|EXTENSION)\b|DROP\b[^;'\"]*\bCASCADE\b|TRUNCATE\s+(TABLE\s+)?[\w.\"]+|"
                      r"DELETE\s+FROM\s+[\w.\"]+\s*(?=;|$|['\"]))", re.I)


def sql_danger(text):
    text = re.sub(r"--[^\n]*", "", text)
    return bool(SQL_DROP.search(text))


# ---------------------------------------------------------------- 판정: 운영 체크아웃 브랜치
def runtime_checkouts():
    """crontab 이 경로로 부르는 ~/git/<repo> = 운영 체크아웃(크론이 그 작업 트리 코드를 그대로 돌린다)."""
    import subprocess
    # 테스트 전용: crontab 대신 이 파일을 읽는다. 훅 프로세스 환경에서만 읽으므로 Bash 안의 export 로는 못 바꾼다.
    fake = os.environ.get("GUARD_TEST_CRONTAB")
    if fake:
        try:
            return runtime_names(open(fake).read())
        except OSError:
            return set()
    try:
        out = subprocess.run(["crontab", "-l"], capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return set()
    return runtime_names(out)


def runtime_names(crontab_text):
    # 주석 줄(# [DISABLED …] 로 꺼 둔 작업)은 크론이 돌리지 않는다 — 꺼 둔 작업의 레포를 운영으로 오인한 적이 있다.
    out = "\n".join(l for l in crontab_text.splitlines() if not l.lstrip().startswith("#"))
    git = os.path.join(HOME, "git")
    names = set(re.findall(re.escape(git) + r"/([A-Za-z0-9_.-]+)", out))
    names |= set(re.findall(r"(?:~|\$HOME)/git/([A-Za-z0-9_.-]+)", out))
    return {os.path.join(git, n) for n in names if os.path.isdir(os.path.join(git, n, ".git"))}


_RUNTIMES = None


def resolve_dir(cur, target):
    if cur is None:
        return None
    t = os.path.expanduser(target)
    t = re.sub(r"\$\{?HOME\}?", HOME, t)
    if "$" in t or "`" in t:
        return None  # 못 푸는 변수 — 추적 중단
    return os.path.normpath(os.path.join(cur, t))


def is_commitish(repo, name):
    import subprocess
    try:
        return subprocess.run(["git", "-C", repo, "rev-parse", "-q", "--verify", name + "^{commit}"],
                              capture_output=True, timeout=3).returncode == 0
    except Exception:
        return True


def in_linked_worktree(repo, root):
    """runtime 체크아웃 아래 놓인 링크드 워크트리(.claude/worktrees/… 등, .git 이 파일)인가."""
    d = repo
    while d.startswith(root + "/"):
        if os.path.isfile(os.path.join(d, ".git")):
            return True
        d = os.path.dirname(d)
    return False


def branch_reason(w, cur):
    global _RUNTIMES
    h = head_index(w)
    if h >= len(w):
        return None
    if w[h] == "gh" and w[h + 1:h + 3] == ["pr", "checkout"]:
        repo, sub, args = cur, "checkout", ["<pr>"]
    elif w[h] == "git":
        repo, i = cur, h + 1
        while i < len(w) and w[i].startswith("-"):
            if w[i] == "-C" and i + 1 < len(w):
                repo = resolve_dir(repo, w[i + 1])
                i += 2
            elif w[i] in ("-c", "--git-dir", "--work-tree"):
                i += 2
            else:
                i += 1
        if i >= len(w) or w[i] not in ("checkout", "switch", "reset", "rebase", "pull"):
            return None
        sub, args = w[i], w[i + 1:]
        if sub in ("reset", "rebase", "pull"):  # merge 는 아님 — main 위에서 머지 후 push 가 정상 배포 흐름
            refs = [a for a in args if not a.startswith("-")]
            if sub == "reset" and "--hard" not in args:
                return None
            if sub == "pull":
                refs = refs[1:]  # 첫 인자는 원격
            ok = {"main", "master", "origin/main", "origin/master", "HEAD", "@{u}", "@{upstream}"}
            if not refs or all(r in ok or re.match(r"^(HEAD|main|master)([~^]\d*|@\{\d+\})+$", r) for r in refs):
                return None
            if sub == "rebase" and any(a in ("--abort", "--continue", "--quit", "--skip") for a in args):
                return None
    else:
        return None
    if repo is None:
        return None
    if _RUNTIMES is None:
        _RUNTIMES = runtime_checkouts()
    root = next((r for r in _RUNTIMES if repo == r or repo.startswith(r + "/")), None)
    if root and in_linked_worktree(repo, root):
        return None
    if not root or "--" in args:
        return None
    creates = any(a in ("-b", "-B", "-c", "-C", "--orphan", "--detach", "-d") for a in args)
    pos = [a for a in args if not a.startswith("-")]
    if not creates and len(pos) == 1 and pos[0] in ("main", "master"):
        return None
    if not creates and pos and sub == "checkout" and all(os.path.exists(os.path.join(repo, p)) for p in pos) \
            and not is_commitish(repo, pos[0]):
        return None  # git checkout <경로> = 파일 복원 (같은 이름 브랜치가 있으면 git 은 브랜치로 읽는다)
    rt = os.path.basename(root)
    return (f"~/git/{rt} is a production checkout that cron runs as-is: switching to or creating a non-main branch changes production code"
            f" — a production checkout left on a research branch never gets deployed fixes. Work in a worktree: "
            f"`git -C ~/git/{rt} worktree add ../{rt}-<name> -b <branch>`.")


# ---------------------------------------------------------------- 조립
LOAD_CTX = re.compile(r"(\bexport|\bdeclare\s+-x|(^|[\s;&|(])(\.|source)|\beval|\b[A-Za-z_]\w*=)\s*$")


SSH_ARG_OPTS = set("pioJlFLRDEbceSmOQWwB")
INTERP = re.compile(r"^(python[\d.]*|node|perl|ruby)$")


def nested_reason(w, cwd, depth, ctx_load=False):
    """bash/sh -c '…', eval …, ssh host '…', python -c '…' 의 안쪽 문자열."""
    h = head_index(w)
    if h >= len(w):
        return None
    cmd = os.path.basename(w[h])
    args = w[h + 1:]
    if cmd in SHELL_INTERP - {"ssh"}:
        for j, a in enumerate(args):
            if re.match(r"^-[a-zA-Z]*c[a-zA-Z]*$", a) and j + 1 < len(args):
                return check_bash(args[j + 1], cwd, ctx_load, depth=depth + 1)
    if cmd == "eval" and args:
        return check_bash(" ".join(args), cwd, ctx_load, depth=depth + 1)
    if cmd == "ssh":
        j = 0
        while j < len(args) and args[j].startswith("-"):
            j += 2 if (len(args[j]) == 2 and args[j][1] in SSH_ARG_OPTS) else 1
        if j + 1 < len(args):
            remote = " ".join(args[j + 1:]).replace("\\$", "$").replace("\\`", "`")  # shlex 는 "…" 안 \$ 를 안 푼다
            return check_bash(remote, "/", ctx_load, depth=depth + 1)
    for j, a in enumerate(w):
        if a in ("-c", "-e") and j + 1 < len(w) and any(INTERP.match(os.path.basename(x)) for x in w[:j]):
            code = w[j + 1]
            # 출력 호출의 괄호 '안'에서 비밀 환경변수를 읽을 때만(접속 인자로 쓰는 건 출력이 아니다)
            for call in re.findall(r"(?:\bprint|console\.log|sys\.stdout\.write|pprint)\s*\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)", code):
                if re.search(r"\bif\b|\bbool\(|\blen\(|\bis\s+(not\s+)?None|\bin\s+os\.environ", call):
                    continue  # 존재·길이만
                for nm in re.findall(r"(?:environ\[|getenv\(|environ\.get\(|process\.env\.?\[?)['\"]?([A-Z_][A-Z0-9_]*)", call):
                    if is_secret_var(nm):
                        return ("env", nm)
            if re.search(r"\bprint\b|console\.log|stdout", code) and re.search(r"\.read(_text)?\(|readFileSync", code):
                for lit in re.findall(r"['\"]([^'\"]+)['\"]", code):
                    if is_secret_path(lit, cwd):
                        return ("secret", lit)
    return None


def check_bash(cmd, cwd, ctx_load=False, depth=0):
    """(종류, 이유|토큰) 또는 None."""
    if not cmd or not isinstance(cmd, str) or depth > 8:
        return None
    main_cmd, bodies = split_heredocs(cmd)
    for kind, body in bodies:
        if kind == "shell":
            r = check_bash(body, cwd)
            if r:
                return r
        elif kind == "sql" and sql_danger(body):
            return ("danger", SQL_MSG)
    pipes, inner = split_commands(main_cmd)
    cur = cwd or os.getcwd()
    for pipe in pipes:
        tok = secret_reason(pipe, cur, ctx_load=ctx_load)
        if tok:
            return ("secret", tok)
        ev = None if ctx_load else env_dump_reason(pipe)
        if ev:
            return ("env", ev)
        if any(os.path.basename((words_of(sg) or [""])[0]) in SQL_INTERP for sg in pipe[1:]) and sql_danger(" ".join(pipe)):
            return ("danger", SQL_MSG)
        for seg in pipe:
            r = nested_reason(words_of(seg), cur, depth, ctx_load)
            if r:
                return r
            r = danger_reason(seg, cur)
            if r:
                return ("danger", r)
            w = words_of(seg)
            hc = head_index(w)
            if hc < len(w) and w[hc] in ("cd", "pushd"):
                cur = resolve_dir(cur, w[hc + 1] if hc + 1 < len(w) else "~")
                continue
            if re.search(r"\b(checkout|switch|reset|merge|rebase|pull)\b", seg):
                r = branch_reason(w, cur)
                if r:
                    return ("danger", r)
    for before, body in inner:
        # 치환 결과는 갇힌다(출력 아님) — 환경변수 출력 판정은 하지 않고, 비밀 읽기는 불러 쓰기 맥락이면 통과
        r = check_bash(body, cwd, ctx_load=ctx_load or bool(LOAD_CTX.search(before)), depth=depth + 1)
        if r and not (r[0] == "env"):
            return r
    return None


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                             "permissionDecisionReason": "[guard] " + reason}}, ensure_ascii=False))
    sys.exit(0)


def secret_msg(tok):
    return (f"Command prints, copies or sends the contents of a secret file ({tok}). To load it use `set -a; . {tok}; set +a` or "
            f"`export $(grep -v '^#' {tok} | xargs)`; key names only: `cut -d= -f1 {tok}`; existence check: `grep -q KEY {tok}`.")


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    if not isinstance(data, dict):
        return
    tool = data.get("tool_name", "")
    ti = data.get("tool_input") or {}
    if not isinstance(ti, dict):
        return
    cwd = data.get("cwd") or ""

    if tool in ("Read", "Edit", "Write", "MultiEdit", "NotebookEdit"):
        p = ti.get("file_path") or ti.get("notebook_path") or ""
        if is_secret_path(p, cwd):
            deny(f"Secret file ({os.path.basename(str(p))}) may not be read or edited. If you need the values, load them in Bash with "
                 f"`set -a; . {p}; set +a` (do not print them). For key names only: `cut -d= -f1 {p}`.")
        return
    if tool == "Grep":
        if is_secret_path(ti.get("path") or "", cwd) or is_secret_path(ti.get("glob") or "", cwd):
            deny("Searching secret file contents is not allowed. For an existence check use Bash `grep -q KEY <file>`.")
        return
    if tool == "Bash":
        r = check_bash(ti.get("command"), cwd)
        if not r:
            return
        kind, v = r
        if kind == "secret":
            deny(secret_msg(v))
        if kind == "env":
            deny(f"Printing env vars ({v}) would expose loaded secrets (DB DSNs, keys, tokens) verbatim. To check presence only use "
                 f"`[ -n \"$VAR\" ] && echo set`; length: `${{#VAR}}`; names only: `env | cut -d= -f1`.")
        deny(v + " If it is truly needed, show the user the command and have them run it themselves (`! <command>`).")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        pass
