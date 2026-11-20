#!/usr/bin/env bash
# check_no_personal.py 자체: 패턴·바이너리·사설 IP 를 잡고, LICENSE·루프백은 넘긴다
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null DOTFILES_PERSONAL="$T/p"
mkdir -p "$T/r/tests" "$T/p"; cp "$REPO/tests/check_no_personal.py" "$T/r/tests/"
printf '%s\n' '\bsecretname\b' > "$T/p/leak-patterns.txt"
cd "$T/r" && git init -q
check() {  # check <파일> <내용(printf)> <hit 기대 0|1>
  rm -f ./*.txt ./*.dat LICENSE
  # shellcheck disable=SC2059  # 내용이 곧 printf 포맷이다(\0, %d 를 쓴다)
  printf "$2" > "$1"
  git add -A
  python3 tests/check_no_personal.py >/dev/null 2>&1; rc=$?
  [ "$rc" = "$3" ] || { echo "FAIL $1: rc=$rc, expected $3"; fail=1; }
}
fail=0
check clean.txt 'nothing here\n' 0
check note.txt 'hello secretname\n' 1
check blob.dat 'a\0b secretname \0c' 1          # 바이너리 안도 본다
check LICENSE 'Copyright (c) secretname\n' 0    # 저작권자 이름은 일부러 공개
check ip.txt 'host 192.168.1.%d\n' 1         # 조립한다 — 이 파일 자체가 검사에 걸리지 않게
check lo.txt 'host 127.0.0.1\n' 0
[ $fail -eq 0 ] && echo "test_check_no_personal: 6/6 pass"
exit $fail
