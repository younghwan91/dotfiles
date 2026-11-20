#!/usr/bin/env bash
# git/hooks 의 신원 검사를 프로필별로 검사한다. 임시 HOME·레포·bare 원격에서 돈다.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/../git/hooks" && pwd)"
export GIT_CONFIG_NOSYSTEM=1 SKIP_CI_LOCAL=1 PUSH_SYNC_SKIP=1
unset GIT_IDENTITY_ALLOWLIST
pass=0 fail=0 tmps=()
trap 'rm -rf "${tmps[@]}"' EXIT

setup() {  # 새 HOME + 레포 + 원격
  export HOME; HOME=$(mktemp -d); tmps+=("$HOME")
  mkdir -p "$HOME/.config/git" "$HOME/.config/dotfiles"
  git init -q --bare "$HOME/remote.git"
  git init -q -b main "$HOME/r"
  git -C "$HOME/r" config core.hooksPath "$HOOKS"
  git -C "$HOME/r" remote add origin "$HOME/remote.git"
}
commit() {  # commit <email> [<message>]
  git -C "$HOME/r" -c user.name=t -c user.email="$1" commit -q --allow-empty -m "${2:-x}" 2>&1
}
push() { git -C "$HOME/r" push -q origin main 2>&1; }
check() {  # check <name> <expect ok|fail> <rc> <output> [<must contain>]
  local got=ok; [ "$3" -ne 0 ] && got=fail
  if [ "$got" = "$2" ] && { [ -z "${5:-}" ] || grep -q "$5" <<<"$4"; }; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL $1: expected $2, got $got"; sed 's/^/    /' <<<"$4" | head -8; fi
}

t_vanilla_no_files() { setup
  out=$(commit a@b.c); check vanilla_no_files ok $? "$out"; }
t_personal_no_allowlist() { setup; echo personal > "$HOME/.config/dotfiles/profile"
  out=$(commit a@b.c); check personal_no_allowlist fail $? "$out" "no allowlist"; }
t_personal_disallowed() { setup; echo personal > "$HOME/.config/dotfiles/profile"; echo x@y.z > "$HOME/.config/git/allowed-emails"
  out=$(commit a@b.c); check personal_disallowed fail $? "$out"; }
t_personal_allowed() { setup; echo personal > "$HOME/.config/dotfiles/profile"; echo x@y.z > "$HOME/.config/git/allowed-emails"
  out=$(commit x@y.z); check personal_allowed ok $? "$out"; }
t_existing_link_no_profile() { setup; echo x@y.z > "$HOME/.config/git/allowed-emails"
  out=$(commit a@b.c); check existing_link_no_profile fail $? "$out"; }
t_blocked_domain_push() { setup; echo '@corp.example' > "$HOME/.config/git/blocked-domains"
  commit a@b.c "mail me@corp.example" >/dev/null; out=$(push); check blocked_domain_push fail $? "$out" "domain"; }
t_no_blocked_file_push() { setup
  commit a@b.c "mail me@corp.example" >/dev/null; out=$(push); check no_blocked_file_push ok $? "$out"; }

t_dangling_allowlist_link() { setup; ln -s "$HOME/moved-away" "$HOME/.config/git/allowed-emails"
  out=$(commit a@b.c); check dangling_allowlist_link fail $? "$out" "broken"; }
t_comment_only_blocked_file_push() { setup; printf '# only a comment\n\n' > "$HOME/.config/git/blocked-domains"
  commit a@b.c "x" >/dev/null; out=$(push); check comment_only_blocked_file_push ok $? "$out"; }

for t in dangling_allowlist_link comment_only_blocked_file_push vanilla_no_files personal_no_allowlist personal_disallowed personal_allowed existing_link_no_profile blocked_domain_push no_blocked_file_push; do
  "t_$t"
done
echo "test_identity: $pass/$((pass + fail)) pass"
[ $fail -eq 0 ]
