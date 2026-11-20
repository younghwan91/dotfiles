#!/usr/bin/env bash
# ssh-keys-sync: GitHub 키 + personal 키로 맞추고, 빠진 키는 지우고, 못 받거나 0개면 건드리지 않는다
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export SSH_KEYS_OWNER=me SSH_KEYS_TARGET="$T/ak" DOTFILES_PERSONAL="$T/p"
mkdir -p "$T/p/ssh"
k() { echo "ssh-ed25519 AAAA$1"; }
{ k gh1; k gh2; } > "$T/gh.keys"
{ echo "# extra"; k extra1 | sed 's/$/ me@box/'; } > "$T/p/ssh/authorized_keys"
{ k gh1; k stale | sed 's/$/ old@gone/'; } > "$T/ak"
fail=0; no() { echo "FAIL $1"; fail=1; }
run() { SSH_KEYS_URL="$1" "$REPO/bin/ssh-keys-sync" "${@:2}" >/dev/null 2>&1; }

run "file://$T/gh.keys" --check && no "check should report a difference"
run "file://$T/gh.keys" || no "sync failed"
if ! { grep -q AAAAgh2 "$T/ak" && grep -q AAAAextra1 "$T/ak"; }; then no "missing keys after sync"; fi
grep -q AAAAstale "$T/ak" && no "stale key kept"
if ! { [ -f "$T/ak.bak-dotfiles" ] && grep -q AAAAstale "$T/ak.bak-dotfiles"; }; then no "no backup"; fi
before=$(cat "$T/ak"); run "file://$T/gh.keys"; [ "$before" = "$(cat "$T/ak")" ] || no "not idempotent"
run "file://$T/gh.keys" --check || no "check should pass after sync"

: > "$T/empty.keys"; run "file://$T/empty.keys" && no "zero keys should fail"
[ "$before" = "$(cat "$T/ak")" ] || no "zero keys changed the file"
run "file://$T/missing.keys" && no "unreachable should fail"
[ "$before" = "$(cat "$T/ak")" ] || no "unreachable changed the file"

[ $fail -eq 0 ] && echo "test_ssh_keys_sync: 9/9 pass"
exit $fail
