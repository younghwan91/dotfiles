#!/usr/bin/env bash
# git/hooks/commit-msg: English-only commit messages. Runs in a temp repo.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/../git/hooks" && pwd)"
export GIT_CONFIG_NOSYSTEM=1 SKIP_CI_LOCAL=1 PUSH_SYNC_SKIP=1
unset COMMIT_MSG_ALLOW_NON_ENGLISH
pass=0 fail=0
R=$(mktemp -d); trap 'rm -rf "$R"' EXIT
git init -q -b main "$R"
git -C "$R" config core.hooksPath "$HOOKS"
git -C "$R" config user.name t; git -C "$R" config user.email t@example.com
export HOME="$R"  # no allowlist profile → identity check off
try() {  # try <name> <expect ok|fail> <message> [env]
  local rc; env ${4:+"$4"} git -C "$R" commit -q --allow-empty -m "$3" >/dev/null 2>&1; rc=$?
  local got=ok; [ $rc -ne 0 ] && got=fail
  if [ "$got" = "$2" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: expected $2, got $got"; fi
}
try english ok "fix(x): handle empty input — with an em dash and ×"
try hangul_subject fail "docs: 리드미 정리"
try hangul_in_body fail $'docs: reword\n\nThe label "자기 키" was unclear.'
try kanji fail "docs: 漢字"
try override ok "docs: 한글" COMMIT_MSG_ALLOW_NON_ENGLISH=1
echo "commit-msg: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
