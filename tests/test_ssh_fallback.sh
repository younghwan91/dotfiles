#!/usr/bin/env bash
# ssh-fallback: 열린 첫 주소로 중계하고, OS 에 맞는 연결 제한 옵션을 쓰고, 중계에는 제한을 넣지 않는다
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# 가짜 nc: -z 탐침은 "up*" 주소만 성공, 그 밖에는 받은 인자를 찍는다. 가짜 uname 으로 OS 를 바꾼다.
cat > "$T/nc" <<'SH'
#!/usr/bin/env bash
echo "nc $*" >> "$NC_LOG"
for a in "$@"; do [ "$a" = -z ] && { case " $* " in *" up"*) exit 0 ;; *) exit 1 ;; esac; }; done
echo "relay $*"
SH
printf '#!/bin/sh\necho "$FAKE_OS"\n' > "$T/uname"
chmod +x "$T/nc" "$T/uname"
export PATH="$T:$PATH" NC_LOG="$T/log"
fail=0; no() { echo "FAIL $1"; fail=1; }
run() { : > "$NC_LOG"; "$REPO/bin/ssh-fallback" "$@" 2>/dev/null; }

out=$(FAKE_OS=Linux run 22 down1 up2 up3)
[ "$out" = "relay up2 22" ] || no "linux picks first open (got: $out)"
grep -q -- '-z -w 2 down1 22' "$NC_LOG" || no "linux probe uses -w"
grep -q 'up3' "$NC_LOG" && no "kept probing after a hit"

out=$(FAKE_OS=Darwin run -t 5 2222 up1)
[ "$out" = "relay up1 2222" ] || no "darwin relay (got: $out)"
grep -q -- '-z -G 5 up1 2222' "$NC_LOG" || no "darwin probe uses -G and -t"

FAKE_OS=Linux run 22 down1 down2 && no "all down should fail"
run 22 && no "missing hosts should be a usage error"

[ $fail -eq 0 ] && echo "test_ssh_fallback: 7/7 pass"
exit $fail
