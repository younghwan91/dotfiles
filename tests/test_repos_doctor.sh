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

# Husky 가 훅을 관리하는 레포는 위임 경고를 내지 않고, 다른 레포 전용 훅 폴더는 계속 경고한다
mkdir -p "$T/git"
for r in husky own; do git init -q "$T/git/$r"; done
mkdir -p "$T/git/husky/.husky/_" "$T/git/own/.githooks"
git -C "$T/git/husky" config core.hooksPath .husky/_
git -C "$T/git/own" config core.hooksPath .githooks
out=$(DOTFILES_PERSONAL="$T/p" "$REPO/bin/repos-doctor" "$T/git" 2>&1)
grep -A3 "husky" <<<"$out" | grep -q "위임 없음" && { echo "FAIL husky repo warned"; fail=1; }
grep -A3 "own" <<<"$out" | grep -q "위임 없음" || { echo "FAIL .githooks repo without delegation not reported"; echo "$out" | tail -8; fail=1; }

# 로컬 ~/.ssh/config 에 공통 호스트가 다시 생기면 경고한다
mkdir -p "$T/p/ssh" "$HOME/.ssh"; printf 'Host box alias\n    HostName box.example\n' > "$T/p/ssh/config"
printf 'Host mine\n    User me\n' > "$HOME/.ssh/config"
out=$(DOTFILES_PERSONAL="$T/p" "$REPO/bin/repos-doctor" "$T/git" 2>&1)
grep -q "공통 호스트가 또 있다" <<<"$out" && { echo "FAIL ssh drift false positive"; fail=1; }
printf 'Host alias\n    HostName other.example\n' >> "$HOME/.ssh/config"
out=$(DOTFILES_PERSONAL="$T/p" "$REPO/bin/repos-doctor" "$T/git" 2>&1)
grep -q "공통 호스트가 또 있다: alias" <<<"$out" || { echo "FAIL ssh drift not reported"; fail=1; }


# crontab: 없는 경로·관리 블록 밖의 줄을 잡고, 출력 파일·mkdir 인자·VAR= 값은 경로 검사에서 뺀다
mkdir -p "$T/ok"; : > "$T/ok/run.sh"
cat > "$T/ct" <<EOF
MAILTO=""
30 1 * * * cd $T/gone && ./run.sh >> $T/gone/log.txt 2>&1
# >>> managed: r (deploy/crontab.h) >>>
0 2 * * * mkdir -p $T/newdir && X=$T/state.file $T/ok/run.sh >> $T/out/x.log 2>&1
5 2 * * * $T/missing/job.sh
6 2 * * * flock -n /tmp/x.lock sh -c "$T/ok/run.sh --flag"
# <<< managed: r <<<
EOF
out=$(REPOS_DOCTOR_CRONTAB="$T/ct" DOTFILES_PERSONAL="$T/p" "$REPO/bin/repos-doctor" "$T/git" 2>&1)
grep -q "2번 줄: cron-install 관리 블록 밖" <<<"$out" || { echo "FAIL unmanaged cron line not reported"; fail=1; }
grep -q "2번 줄: 없는 경로 $T/gone " <<<"$out" || { echo "FAIL missing cd dir not reported"; fail=1; }
grep -q "5번 줄 \[r\]: 없는 경로 $T/missing/job.sh" <<<"$out" || { echo "FAIL missing script not reported"; fail=1; }
grep "없는 경로" <<<"$out" | grep -qE "newdir|state.file|x.log|log.txt" && { echo "FAIL cron false positive"; grep -E "newdir|state|log" <<<"$out"; fail=1; }

# 폴더 이름이 origin 레포 이름과 다르면 경고한다
git init -q "$T/git/oldname"; git -C "$T/git/oldname" remote add origin https://github.com/o/newname.git
out=$(DOTFILES_PERSONAL="$T/p" "$REPO/bin/repos-doctor" "$T/git" 2>&1)
grep -A3 "oldname" <<<"$out" | grep -q "origin 레포(newname)와 다름" || { echo "FAIL folder/origin name mismatch not reported"; fail=1; }

[ $fail -eq 0 ] && echo "test_repos_doctor: 12/12 pass"
exit $fail
