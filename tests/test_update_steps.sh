#!/usr/bin/env bash
# `update` must announce each step ("==> [n/N]") so the user can see what is running,
# keep going when one step fails, and report the failed steps at the end.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
no() { echo "FAIL $1"; fail=1; }

# Linux: run the zsh function with every external tool stubbed out.
run() { zsh -fc "sudo(){ $1 }; uv(){ :; }; npm(){ :; }; fwupdmgr(){ return 2; }; source zsh/os/linux.zsh; update" 2>&1; }

out=$(run ':;') && rc=0 || rc=$?
total=$(grep -o '\[1/[0-9]*\]' <<<"$out" | head -1 | tr -dc 0-9 | cut -c2-)
[ -n "$total" ] && [ "$total" -ge 3 ] || no "linux update: no [1/N] header"
for n in $(seq 1 "${total:-3}"); do
  grep -q "\[$n/$total\]" <<<"$out" || no "linux update: no [$n/$total] header"
done
grep -q "update done" <<<"$out" && [ $rc -eq 0 ] || no "linux update: success path (rc=$rc)"
grep -q "firmware check" <<<"$out" || [ -n "${WSL_DISTRO_NAME:-}" ] || ! command -v fwupdmgr >/dev/null \
  || no "linux update: fwupdmgr exit 2 (no updates) should not count as failure"

out=$(run '[[ $2 == autoremove ]] && return 1; return 0;') && rc=0 || rc=$?
grep -q "\[$total/$total\]" <<<"$out" || no "linux update: stopped after a failed step"
grep -q "apt autoremove" <<<"$(grep -A0 '실패한 단계' <<<"$out")" && [ $rc -ne 0 ] \
  || no "linux update: failed step not reported (rc=$rc)"

# Windows: update.cmd can't run here, so check every step has its header.
for n in 1 2 3 4 5; do
  grep -q "\[$n/5\]" windows/bin/update.cmd || no "update.cmd: no [$n/5] header"
done

[ $fail -eq 0 ] && echo "PASS update steps"
exit $fail
