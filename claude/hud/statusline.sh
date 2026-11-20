#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "unknown"')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "~"')
# Windows(Git Bash)는 cwd 를 백슬래시로 준다. 슬래시로 바꾼다 — 경로에 "\c" 같은 열이 있으면
# printf %b / echo -e 출력이 거기서 끊겨 뒤 줄이 전부 사라진다.
CWD=${CWD//\\//}
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
FIVE_HOUR_USED=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
SEVEN_DAY_USED=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
FIVE_HOUR_RESETS_AT=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
SEVEN_DAY_RESETS_AT=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
SESSION_NAME=$(echo "$input" | jq -r '.session_name // empty')
SESSION_ID=$(echo "$input" | jq -r '.session_id // empty')

DIR_NAME="${CWD##*/}"

# 파스텔 256색 팔레트
C_RESET="\033[0m"
C_MODEL="\033[38;5;183m"   # 라벤더
C_DIR="\033[38;5;153m"     # 하늘색
C_BRANCH="\033[38;5;158m"  # 민트
C_CPU="\033[38;5;216m"     # 복숭아색
C_MEM="\033[38;5;111m"     # 연파랑
C_GPU="\033[38;5;183m"     # 라벤더
C_ENV="\033[38;5;224m"     # 연장미색
C_WEATHER="\033[38;5;159m" # 연청록
C_HOST="\033[38;5;229m"    # 버터 노랑(태그만 paint() 가 굵게, 나머지는 보통)
C_SESSION="\033[38;5;223m" # 연복숭아색

# ============================================================================
# 열 배치
#
# 모든 줄은 고정된 "슬롯"(아이콘 + 글) 순서로 만든다. 어떤 선택 데이터가
# 있든 순서와 폭은 늘 같다. 슬롯에 데이터가 없으면(venv 없음, 아직 한도
# 데이터 없음, CPU 온도 센서 없음 등) 빼지 않고 같은 폭의 *빈 칸*으로
# 채운다 — 그래야 뒤 슬롯(과 다른 줄의 같은 슬롯)이 늘 같은 열에 선다.
#
#   슬롯 1  ->  COL_AB  (model / 7d / cpu       / gpu-util / weather)
#   슬롯 2  ->  COL_AB  (dir   / 5h / mem        / gpu-mem  / session)
#   슬롯 3  ->  COL_C   (env   / ctx / cpu-temp  / gpu-temp)
#   슬롯 4  ->  COL_D   (branch+sha — 4번째 슬롯은 1번 줄에만 있다)
#
# 브랜치의 커밋 sha 와 에이전트 이름은 슬롯을 따로 갖지 않는다. sha 는
# 브랜치 칸 뒤에 붙이고(BRN main #a1b2c3), 에이전트 이름은 날씨 줄의 2번째
# COL_AB 슬롯을 쓴다(WX ...  AGT name). 그래서 열 경계를 새로 만들지 않는다.
#
# 슬롯 사이는 "·" 글리프 없이 공백 두 칸(SEP="  ")이다 — 더 좁고, 색칠·폭
# 계산할 것도 하나 준다.
#
# 각 열의 폭은 임의 글이 아니라 그 열에 오는 *고정 형식* 값(막대 + 퍼센트 +
# 단위) 중 가장 넓은 것에 맞춘다 — 보통 경우를 자르지 않는 최소 폭이다.
#   COL_AB=35: "MEM <bar> 100% (999.9/999.9GB)" 가 가장 넓다(mem/vram 은 GB,
#              예전 "(resets ...)" 대신 "in <time>").
#   COL_C=19:  "CTX <bar> 100%" 가 가장 넓다.
#   COL_D=28:  "BRN main #a1b2c3 ● ↑9 ↓9" 가 들어간다. 더 긴 브랜치 이름은 자른다.
# 글만 있는 칸(모델·디렉터리·venv·브랜치 이름, 날씨, 에이전트 이름)도 같은
# 방식으로 재고, 넘치면 열을 깨지 않고 말줄임("…")으로 자른다. 줄바꿈이나
# 밀림 없이 늘 정렬되게 하는 대가다.
#
# 폭은 색을 입히기 전 *맨 글*(ANSI 색 코드 없음)로 재므로 이스케이프가 채움
# 계산을 흐트러뜨리지 않는다. 접두어는 이모지가 아니라 ASCII 3글자 태그(MDL,
# DIR, 7DY, CPU, ...)라 어디서나 한 글자 = 터미널 한 칸이다 — 글꼴·터미널에
# 따라 아이콘 폭을 추측할 일이 없다. 막대 문자(█/░)는 고정폭 글꼴이 그리는
# 대로 1칸으로 친다.
#
# DIR/BRANCH/ENV 에는 여전히 임의 글(한글 폴더·브랜치 이름 등)이 올 수 있다.
# CJK 글자는 터미널 2칸인데 bash `${#text}` 는 1로 세므로, bash 만으로
# 채움·자르기를 하면 그런 글에서 정렬이 어긋난다. 그래서 칸 맞추기는 전부
# `node` 한 번 호출(아래 fit_all)에 맡긴다 — 실제 표시 폭을 재서 모든 슬롯의
# 자르고 채운 맨 글을 프로세스 하나로 돌려준다.
# ============================================================================
COL_AB=35
COL_C=19
COL_D=28
SEP="  "

bar() {
  local pct=$1 filled i out=""
  filled=$((pct / 10))
  [ "$filled" -gt 10 ] && filled=10
  [ "$filled" -lt 0 ] && filled=0
  for i in $(seq 1 10); do
    if [ "$i" -le "$filled" ]; then out="${out}█"; else out="${out}░"; fi
  done
  echo "$out"
}

fmt_remaining() {
  local target_epoch=$1 now diff d h m
  [ -z "$target_epoch" ] && return
  target_epoch="${target_epoch%%.*}"
  now=$(date +%s)
  diff=$((target_epoch - now))
  [ "$diff" -lt 0 ] && diff=0
  d=$((diff / 86400))
  h=$(((diff % 86400) / 3600))
  m=$(((diff % 3600) / 60))
  if [ "$d" -gt 0 ]; then
    printf "%dd%dh" "$d" "$h"
  elif [ "$h" -gt 0 ]; then
    printf "%dh%dm" "$h" "$m"
  else
    printf "%dm" "$m"
  fi
}

pct_color() {
  local pct=$1
  if [ "$pct" -lt 50 ]; then echo "\033[38;5;158m"       # 민트
  elif [ "$pct" -lt 80 ]; then echo "\033[38;5;229m"      # 버터 노랑
  else echo "\033[38;5;217m"; fi                          # 파스텔 분홍/빨강
}

# 퍼센트를 3칸 고정 폭으로 오른쪽 정렬한다("5" -> "  5", "62" -> " 62").
# 자릿수와 상관없이 "<bar> <pct>%" 묶음 폭이 같아진다.
pad3() {
  printf "%3d" "$1"
}

# 모든 슬롯의 맨 글을 node 프로세스 하나에서 목표 폭에 맞춘다. bash 의
# 바이트·글자 수가 아니라 실제 터미널 표시 폭(CJK·넓은 글자 = 2칸)으로 잰다.
# 인자는 (글, 폭) 쌍, 출력은 같은 순서로 한 줄에 하나씩 맞춘 글("…"로 자르거나
# 공백으로 채움)이다. 한글 등 넓은 글자의 폴더·브랜치·env 이름에서도
# ${#text} 로 인한 어긋남이 생기지 않는다.
fit_all() {
  node -e '
    const wide = c => (c >= 0x1100 && (c <= 0x115F || c === 0x2329 || c === 0x232A
      || (c >= 0x2E80 && c <= 0xA4CF) || (c >= 0xAC00 && c <= 0xD7A3)
      || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFE30 && c <= 0xFE6F)
      || (c >= 0xFF00 && c <= 0xFF60) || (c >= 0xFFE0 && c <= 0xFFE6)
      || (c >= 0x1F300 && c <= 0x1FAFF) || (c >= 0x2600 && c <= 0x27BF)));
    const dispWidth = s => {
      let n = 0;
      for (const ch of s) {
        const c = ch.codePointAt(0);
        if (c === 0xFE0F || c === 0xFE0E || c === 0x200D || (c >= 0x0300 && c <= 0x036F)) continue;
        n += wide(c) ? 2 : 1;
      }
      return n;
    };
    const fit = (text, width) => {
      const dw = dispWidth(text);
      if (dw <= width) return text + " ".repeat(width - dw);
      let out = "", w = 0;
      for (const ch of text) {
        const cw = dispWidth(ch);
        if (w + cw > width - 1) break;
        out += ch; w += cw;
      }
      out += "…"; w += 1;
      return out + " ".repeat(Math.max(0, width - w));
    };
    const args = process.argv.slice(1);
    const out = [];
    for (let i = 0; i < args.length; i += 2) out.push(fit(args[i], parseInt(args[i + 1], 10)));
    process.stdout.write(out.join("\n") + "\n");
  ' "$@"
}

# 이미 폭을 맞춘 슬롯 글에 ANSI 색을 입힌다.
# 굵게는 3글자 태그(MDL, DIR, BRN, ...)만, 뒤 값은 보통 — PC 도 이제 통째로
# 굵게 하지 않고 똑같이 처리한다.
paint() {
  local text="$1" color="$2" tag="" rest="$text"
  if [[ "$text" == *" "* ]]; then
    tag="${text%% *}"
    rest="${text#"$tag"}"
  else
    tag="$text"
    rest=""
  fi
  printf "%b\033[1m%s%b%b%s%b" "$color" "$tag" "$C_RESET" "$color" "$rest" "$C_RESET"
}

# ---- 1번 줄: 모델 / 디렉터리 / venv / 브랜치 ----
MODEL_TXT="MDL ${MODEL}"
DIR_TXT="DIR ${DIR_NAME}"

ENV_NAME=""
if [ -n "$VIRTUAL_ENV" ]; then
  ENV_NAME=$(basename "$VIRTUAL_ENV")
elif [ -n "$CONDA_DEFAULT_ENV" ] && [ "$CONDA_DEFAULT_ENV" != "base" ]; then
  ENV_NAME="$CONDA_DEFAULT_ENV"
fi
ENV_TXT="ENV ${ENV_NAME:---}"

BRANCH_TXT=""
if git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1; then
  BRANCH_NAME=$(git -C "$CWD" branch --show-current 2>/dev/null)
  GIT_SHA=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
  BRANCH_TXT="BRN ${BRANCH_NAME}"
  [ -n "$GIT_SHA" ] && BRANCH_TXT="${BRANCH_TXT} #${GIT_SHA}"
  if [ -n "$(git -C "$CWD" status --porcelain 2>/dev/null)" ]; then
    BRANCH_TXT="${BRANCH_TXT} ●"
  fi
  COUNTS=$(git -C "$CWD" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)
  if [ -n "$COUNTS" ]; then
    read -r BEHIND AHEAD <<< "$COUNTS"
    [ "${AHEAD:-0}" -gt 0 ] 2>/dev/null && BRANCH_TXT="${BRANCH_TXT} ↑${AHEAD}"
    [ "${BEHIND:-0}" -gt 0 ] 2>/dev/null && BRANCH_TXT="${BRANCH_TXT} ↓${BEHIND}"
  fi
fi
# 참고: 변경 표시 점과 ahead/behind 수는 예전엔 브랜치 이름과 다른 색(복숭아/금색)
# 이었다. 이제 브랜치의 민트색을 같이 쓴다 — 4번째 열을 맞추려면 브랜치 칸
# 전체를 맨 글 하나로 재고 잘라야 해서다. 이 칸이 표 배치를 절대 깨지 않게
# 하는 대가다.

# ---- 2번 줄: 7일 한도 / 5시간 한도 / 컨텍스트 ----
SEVEN_DAY_TXT=""
SEVEN_DAY_COLOR=""
if [ -n "$SEVEN_DAY_USED" ]; then
  SEVEN_DAY_PCT=$(awk -v u="$SEVEN_DAY_USED" 'BEGIN{printf "%d", u}')
  SEVEN_DAY_BAR=$(bar "$SEVEN_DAY_PCT")
  SEVEN_DAY_COLOR=$(pct_color "$SEVEN_DAY_PCT")
  SEVEN_DAY_PCT_S=$(pad3 "$SEVEN_DAY_PCT")
  SEVEN_DAY_RESET_STR=$(fmt_remaining "$SEVEN_DAY_RESETS_AT")
  SEVEN_DAY_TXT="7DY ${SEVEN_DAY_BAR} ${SEVEN_DAY_PCT_S}%"
  [ -n "$SEVEN_DAY_RESET_STR" ] && SEVEN_DAY_TXT="${SEVEN_DAY_TXT} in ${SEVEN_DAY_RESET_STR}"
fi

FIVE_HOUR_TXT=""
FIVE_HOUR_COLOR=""
if [ -n "$FIVE_HOUR_USED" ]; then
  FIVE_HOUR_PCT=$(awk -v u="$FIVE_HOUR_USED" 'BEGIN{printf "%d", u}')
  FIVE_HOUR_BAR=$(bar "$FIVE_HOUR_PCT")
  FIVE_HOUR_COLOR=$(pct_color "$FIVE_HOUR_PCT")
  FIVE_HOUR_PCT_S=$(pad3 "$FIVE_HOUR_PCT")
  FIVE_HOUR_RESET_STR=$(fmt_remaining "$FIVE_HOUR_RESETS_AT")
  FIVE_HOUR_TXT="5HR ${FIVE_HOUR_BAR} ${FIVE_HOUR_PCT_S}%"
  [ -n "$FIVE_HOUR_RESET_STR" ] && FIVE_HOUR_TXT="${FIVE_HOUR_TXT} in ${FIVE_HOUR_RESET_STR}"
fi

CTX_COLOR=$(pct_color "$PCT")
CTX_BAR=$(bar "$PCT")
CTX_PCT_S=$(pad3 "$PCT")
CTX_TXT="CTX ${CTX_BAR} ${CTX_PCT_S}%"

# ---- 3번 줄: cpu / 메모리 / 온도 ----
# Windows(Git Bash)에는 top/free 가 없다. CPU·메모리를 PowerShell 로 읽어 ~10초 캐시하고
# 백그라운드에서 갱신해 상태줄이 기다리지 않게 한다. Linux/macOS 는 그대로.
WIN_STAT=""
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*)
  WS="${TEMP:-/tmp}/hud-winstat"
  if [ ! -f "$WS" ] || [ -n "$(find "$WS" -mmin +0.17 2>/dev/null)" ]; then
    ( powershell.exe -NoProfile -Command '$c=(Get-CimInstance Win32_Processor|Measure-Object LoadPercentage -Average).Average;$o=Get-CimInstance Win32_OperatingSystem;"{0} {1} {2}" -f [int]$c,[int]($o.TotalVisibleMemorySize/1024),[int](($o.TotalVisibleMemorySize-$o.FreePhysicalMemory)/1024)' > "$WS.tmp" 2>/dev/null && mv -f "$WS.tmp" "$WS" ) >/dev/null 2>&1 &
  fi
  [ -f "$WS" ] && WIN_STAT=$(tr -d '\r' < "$WS")
;; esac

CPU_IDLE=$(top -bn1 2>/dev/null | awk -F',' '/Cpu\(s\)/{for(i=1;i<=NF;i++) if($i ~ /id/) print $i}' | grep -o '[0-9.]*')
CPU_PCT=100
if [ -n "$WIN_STAT" ]; then
  CPU_PCT=$(echo "$WIN_STAT" | awk '{print $1}')
elif [ -n "$CPU_IDLE" ]; then
  CPU_PCT=$(awk -v idle="$CPU_IDLE" 'BEGIN{printf "%d", 100-idle}')
fi
CPU_COLOR=$(pct_color "$CPU_PCT")
CPU_BAR=$(bar "$CPU_PCT")
CPU_TXT="CPU ${CPU_BAR} $(pad3 "$CPU_PCT")%"

if [ -n "$WIN_STAT" ]; then
  read -r _ MEM_TOTAL MEM_USED <<< "$WIN_STAT"
else
  read -r MEM_TOTAL MEM_USED <<< "$(free -m 2>/dev/null | awk '/^Mem:/{print $2, $3}')"
fi
MEM_PCT=0
[ -n "$MEM_TOTAL" ] && [ "$MEM_TOTAL" -gt 0 ] && MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
MEM_COLOR=$(pct_color "$MEM_PCT")
MEM_BAR=$(bar "$MEM_PCT")
MEM_USED_GB=$(awk -v m="$MEM_USED" 'BEGIN{printf "%.1f", m/1024}')
MEM_TOTAL_GB=$(awk -v m="$MEM_TOTAL" 'BEGIN{printf "%.1f", m/1024}')
MEM_TXT="MEM ${MEM_BAR} $(pad3 "$MEM_PCT")% (${MEM_USED_GB}/${MEM_TOTAL_GB}GB)"

TEMP=""
TZ_PATH=$(grep -l "x86_pkg_temp" /sys/class/thermal/thermal_zone*/type 2>/dev/null | head -1 | sed 's/type$/temp/')
# Jetson(Thor): x86_pkg_temp 가 없고 CPU 센서 이름은 "cpu-thermal"
[ -z "$TZ_PATH" ] && TZ_PATH=$(grep -lx "cpu-thermal" /sys/class/thermal/thermal_zone*/type 2>/dev/null | head -1 | sed 's/type$/temp/')
[ -z "$TZ_PATH" ] && TZ_PATH=$(ls /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1)
if [ -n "$TZ_PATH" ] && [ -r "$TZ_PATH" ]; then
  TEMP=$(awk '{printf "%d", $1/1000}' "$TZ_PATH")
fi
TEMP_COLOR="\033[38;5;158m"
TEMP_TXT=""
if [ -n "$TEMP" ]; then
  if [ "$TEMP" -ge 80 ]; then TEMP_COLOR="\033[38;5;217m"
  elif [ "$TEMP" -ge 60 ]; then TEMP_COLOR="\033[38;5;229m"; fi
  TEMP_TXT="CTM ${TEMP}°C"
fi

# 기계 이름(hostname), 브랜치 아래 4번째 열
PC_TXT="PC  $(hostname 2>/dev/null)"

# ---- 4번 줄: gpu (nvidia-smi 가 될 때만) ----
GPU_UTIL_TXT=""; GPU_UTIL_COLOR=""
GPU_MEM_TXT=""; GPU_MEM_COLOR=""
GPU_TEMP_TXT=""; GPU_TEMP_COLOR=""
HAS_GPU=0
GPU_INFO=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
# Jetson(Thor)은 통합 메모리라 nvidia-smi 가 메모리를 [N/A] 로 준다. 그래서
# 거기선 VRM 슬롯을 비워 둔다(시스템 RAM 은 이미 MEM 줄에 있다).
if echo "$GPU_INFO" | grep -qE '^[0-9]+, *[0-9]+, *([0-9]+|\[N/A\]), *([0-9]+|\[N/A\])$'; then
  HAS_GPU=1
  IFS=',' read -r GPU_TEMP GPU_UTIL GPU_MEM_USED GPU_MEM_TOTAL <<< "$(echo "$GPU_INFO" | tr -d ' ')"

  GPU_UTIL_COLOR=$(pct_color "$GPU_UTIL")
  GPU_UTIL_BAR=$(bar "$GPU_UTIL")
  GPU_UTIL_TXT="GPU ${GPU_UTIL_BAR} $(pad3 "$GPU_UTIL")%"

  if [ "$GPU_MEM_TOTAL" -gt 0 ] 2>/dev/null; then
    GPU_MEM_PCT=$((GPU_MEM_USED * 100 / GPU_MEM_TOTAL))
    GPU_MEM_COLOR=$(pct_color "$GPU_MEM_PCT")
    GPU_MEM_BAR=$(bar "$GPU_MEM_PCT")
    GPU_MEM_USED_GB=$(awk -v m="$GPU_MEM_USED" 'BEGIN{printf "%.1f", m/1024}')
    GPU_MEM_TOTAL_GB=$(awk -v m="$GPU_MEM_TOTAL" 'BEGIN{printf "%.1f", m/1024}')
    GPU_MEM_TXT="VRM ${GPU_MEM_BAR} $(pad3 "$GPU_MEM_PCT")% (${GPU_MEM_USED_GB}/${GPU_MEM_TOTAL_GB}GB)"
  fi

  GPU_TEMP_COLOR="\033[38;5;158m"
  if [ "$GPU_TEMP" -ge 80 ]; then GPU_TEMP_COLOR="\033[38;5;217m"
  elif [ "$GPU_TEMP" -ge 60 ]; then GPU_TEMP_COLOR="\033[38;5;229m"; fi
  GPU_TEMP_TXT="GTM ${GPU_TEMP}°C"
fi

# ---- 5번 줄: 날씨 (30분 캐시, 실패해도 막지 않음) ----
WEATHER_TXT=""
CACHE_FILE="$HOME/.claude/.statusline_weather_cache"
NOW=$(date +%s)
CACHE_AGE=999999
if [ -f "$CACHE_FILE" ]; then
  CACHE_TS=$(sed -n '1p' "$CACHE_FILE")
  [ -n "$CACHE_TS" ] && CACHE_AGE=$((NOW - CACHE_TS))
fi
if [ "$CACHE_AGE" -gt 1800 ]; then
  FRESH=$(timeout 2 curl -s 'wttr.in/?format=%l|%C|%t' 2>/dev/null)
  if echo "$FRESH" | grep -qE '^[^|]+\|[^|]+\|[+-]?[0-9]+'; then
    { echo "$NOW"; echo "$FRESH"; } > "$CACHE_FILE"
  fi
fi
if [ -f "$CACHE_FILE" ]; then
  WEATHER_RAW=$(sed -n '2p' "$CACHE_FILE")
  IFS='|' read -r W_LOC W_COND W_TEMP <<< "$WEATHER_RAW"
  W_CITY="${W_LOC%%,*}"
  if [ -n "$W_CITY" ] && [ -n "$W_TEMP" ]; then
    WEATHER_TXT="WX ${W_CITY} ${W_COND} ${W_TEMP}"
  fi
fi

# ---- 5번 줄 2번째 슬롯: 다른 세션이 이 세션에 메시지를 보낼 때 쓰는 에이전트
# 이름(ListAgents / SendMessage({to: name}) 에 보이는 것). `claude agents --json`
# 에서 session_id 로 찾는다. CLI 를 못 부르거나(예: PATH 가 빈약한 비대화형 셸)
# 목록에 이 세션이 없으면 /rename 제목, 그다음 session id 원문으로 대신한다.
AGENT_NAME=""
CLAUDE_BIN=$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")
if [ -x "$CLAUDE_BIN" ] && [ -n "$SESSION_ID" ]; then
  AGENT_NAME=$(timeout 2 "$CLAUDE_BIN" agents --json 2>/dev/null | node -e '
    let s = "";
    process.stdin.on("data", d => s += d).on("end", () => {
      try {
        const arr = JSON.parse(s);
        const hit = arr.find(a => a.sessionId === process.argv[1]);
        if (hit && hit.name) process.stdout.write(hit.name);
      } catch (e) {}
    });
  ' "$SESSION_ID")
fi

SESSION_TXT=""
if [ -n "$AGENT_NAME" ]; then
  SESSION_TXT="AGT ${AGENT_NAME}"
elif [ -n "$SESSION_NAME" ]; then
  SESSION_TXT="AGT ${SESSION_NAME}"
elif [ -n "$SESSION_ID" ]; then
  SESSION_TXT="AGT ${SESSION_ID:0:8}"
fi

# node 한 번 호출로 모든 슬롯의 맨 글을 정해진 순서대로 열 폭에 맞춘다(표시 폭
# 기준). 그다음 맞춘 글마다 제 색을 입혀 줄을 조립한다.
mapfile -t FIT < <(fit_all \
  "$MODEL_TXT" "$COL_AB" "$DIR_TXT" "$COL_AB" "$ENV_TXT" "$COL_C" "$BRANCH_TXT" "$COL_D" \
  "$FIVE_HOUR_TXT" "$COL_AB" "$SEVEN_DAY_TXT" "$COL_AB" "$CTX_TXT" "$COL_C" \
  "$CPU_TXT" "$COL_AB" "$MEM_TXT" "$COL_AB" "$TEMP_TXT" "$COL_C" "$PC_TXT" "$COL_D" \
  "$GPU_UTIL_TXT" "$COL_AB" "$GPU_MEM_TXT" "$COL_AB" "$GPU_TEMP_TXT" "$COL_C" \
  "$WEATHER_TXT" "$COL_AB" "$SESSION_TXT" "$COL_AB")

LINE1="$(paint "${FIT[0]}" "$C_MODEL")${SEP}$(paint "${FIT[1]}" "$C_DIR")${SEP}$(paint "${FIT[2]}" "$C_ENV")${SEP}$(paint "${FIT[3]}" "$C_BRANCH")"
LINE2="$(paint "${FIT[4]}" "$FIVE_HOUR_COLOR")${SEP}$(paint "${FIT[5]}" "$SEVEN_DAY_COLOR")${SEP}$(paint "${FIT[6]}" "$CTX_COLOR")"
LINE3="$(paint "${FIT[7]}" "$CPU_COLOR")${SEP}$(paint "${FIT[8]}" "$MEM_COLOR")${SEP}$(paint "${FIT[9]}" "$TEMP_COLOR")${SEP}$(paint "${FIT[10]}" "$C_HOST")"

LINE4=""
[ "$HAS_GPU" -eq 1 ] && LINE4="$(paint "${FIT[11]}" "$GPU_UTIL_COLOR")${SEP}$(paint "${FIT[12]}" "$GPU_MEM_COLOR")${SEP}$(paint "${FIT[13]}" "$GPU_TEMP_COLOR")"

LINE5=""
if [ -n "$WEATHER_TXT" ] || [ -n "$SESSION_TXT" ]; then
  LINE5="$(paint "${FIT[14]}" "$C_WEATHER")${SEP}$(paint "${FIT[15]}" "$C_SESSION")"
fi

printf "%b\n%b\n%b\n" "$LINE1" "$LINE2" "$LINE3"
if [ -n "$LINE4" ]; then
  printf "%b\n" "$LINE4"
fi
if [ -n "$LINE5" ]; then
  printf "%b\n" "$LINE5"
fi
exit 0
