#!/usr/bin/env bash
# repos-doctor 가 personal 레포 없음 / 뒤처짐을 잡는지
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.config/dotfiles"; echo personal > "$HOME/.config/dotfiles/profile"
fail=0

out=$(DOTFILES_PERSONAL="$T/missing" "$REPO/bin/repos-doctor" 2>&1)
grep -q "personal 레포가 없다" <<<"$out" || { echo "FAIL missing personal not reported"; fail=1; }

git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/p" 2>/dev/null
git -C "$T/p" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m one
git -C "$T/p" push -q origin HEAD 2>/dev/null
git clone -q "$T/origin.git" "$T/ahead"
git -C "$T/ahead" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m two
git -C "$T/ahead" push -q origin HEAD 2>/dev/null
git -C "$T/p" fetch -q
out=$(DOTFILES_PERSONAL="$T/p" "$REPO/bin/repos-doctor" 2>&1)
grep -q "1커밋 뒤" <<<"$out" || { echo "FAIL behind personal not reported"; echo "$out" | grep -i personal; fail=1; }

[ $fail -eq 0 ] && echo "test_repos_doctor: 2/2 pass"
exit $fail
