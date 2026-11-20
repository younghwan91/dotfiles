#!/usr/bin/env bash
# windows/*.ps1 이 PowerShell 파서를 통과하는지 — Windows 를 CI 에서 돌릴 수 없어 문법만 본다.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v pwsh >/dev/null || { echo "test_powershell: pwsh 없음 — 건너뜀 (GitHub 러너에는 있다)"; exit 0; }
mapfile -t files < <(git ls-files '*.ps1')
pwsh -NoProfile -Command '
  $bad = 0
  foreach ($f in $args) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$null, [ref]$errs)
    foreach ($e in $errs) { Write-Host "$f:$($e.Extent.StartLineNumber): $($e.Message)"; $bad++ }
  }
  Write-Host "test_powershell: $($args.Count) files, $bad error(s)"
  exit [int]($bad -gt 0)
' "${files[@]}"
