#!/usr/bin/env bash
# pull-all: ~/git/<레포> 와 그 안에 clone 된 <레포>/personal 둘 다 fast-forward 하고, personal 은 이름을 붙여 보인다
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
mk() {  # mk <bare> <clone>
  git init -q --bare -b main "$1"
  git clone -q "$1" "$2" 2>/dev/null
  git -C "$2" commit -q --allow-empty -m one && git -C "$2" push -q origin HEAD:main 2>/dev/null
  git -C "$2" branch -q --set-upstream-to=origin/main 2>/dev/null
}
mk "$T/o-dot.git" "$T/git/dotfiles"
mk "$T/o-per.git" "$T/git/dotfiles/personal"
for o in o-dot o-per; do  # 원격에 새 커밋 하나씩
  git clone -q "$T/$o.git" "$T/w-$o" 2>/dev/null
  git -C "$T/w-$o" commit -q --allow-empty -m two && git -C "$T/w-$o" push -q origin HEAD:main 2>/dev/null
done
out=$("$REPO/bin/pull-all" "$T/git" 2>&1)
fail=0
[ "$(git -C "$T/git/dotfiles" log --oneline | wc -l)" = 2 ] || { echo "FAIL dotfiles not fast-forwarded"; fail=1; }
[ "$(git -C "$T/git/dotfiles/personal" log --oneline | wc -l)" = 2 ] || { echo "FAIL personal not fast-forwarded"; fail=1; }
grep -q "dotfiles/personal" <<<"$out" || { echo "FAIL personal not labelled"; echo "$out" | tail -5; fail=1; }
[ $fail -eq 0 ] && echo "test_pull_all: 3/3 pass"
exit $fail
