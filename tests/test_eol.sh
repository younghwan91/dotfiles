#!/usr/bin/env bash
# Windows cmd 스크립트는 CRLF 로 체크아웃돼야 한다 (cmd 는 LF 파일에서 goto 레이블을 잘못 찾을 수 있다)
set -euo pipefail
cd "$(dirname "$0")/.."
bad=0
while IFS= read -r f; do
  [ "$(git check-attr eol -- "$f" | awk '{print $NF}')" = crlf ] || { echo "FAIL $f: .gitattributes 에 eol=crlf 가 없다"; bad=1; }
done < <(git ls-files '*.cmd' '*.bat')
[ $bad -eq 0 ] && echo "test_eol: cmd/bat 은 CRLF"
exit $bad
