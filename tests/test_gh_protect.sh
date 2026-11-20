#!/usr/bin/env bash
# gh-protect: 규칙 없는 공개 레포에만 ruleset 을 걸고, --check 는 보고만 한다. gh 는 가짜(상태는 파일).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"; touch "$T/state/has-a"     # 레포 a 는 이미 있음, b 는 없음
cat > "$T/bin/gh" <<'SH'
#!/usr/bin/env bash
S=$GH_STATE
case "$*" in
  "api user -q .login") echo me ;;
  "repo list me"*) printf 'a\nb\n' ;;
  "api repos/me/"*"/rulesets -q"*) r=${2#repos/me/}; r=${r%/rulesets}; [ -f "$S/has-$r" ] && echo 1 || echo 0 ;;
  "api -X POST repos/me/"*"/rulesets --input -") r=${4#repos/me/}; r=${r%/rulesets}; cat >/dev/null; touch "$S/has-$r"; echo "{}" >> "$S/posts" ;;
  *) echo "unexpected gh $*" >&2; exit 9 ;;
esac
SH
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" GH_STATE="$T/state"
fail=0; no() { echo "FAIL $1"; fail=1; }

out=$("$REPO/bin/gh-protect" --check 2>&1) && no "check should exit 1 when b is missing"
grep -q "me/b" <<<"$out" || no "check did not name b"
[ -f "$T/state/has-b" ] && no "check must not change anything"
"$REPO/bin/gh-protect" >/dev/null 2>&1 || no "apply failed"
[ -f "$T/state/has-b" ] || no "b not protected"
[ "$(wc -l < "$T/state/posts")" = 1 ] || no "should POST exactly once"
"$REPO/bin/gh-protect" >/dev/null 2>&1; [ "$(wc -l < "$T/state/posts")" = 1 ] || no "second run posted again"
"$REPO/bin/gh-protect" --check >/dev/null 2>&1 || no "check should pass after apply"

[ $fail -eq 0 ] && echo "test_gh_protect: 7/7 pass"
exit $fail
