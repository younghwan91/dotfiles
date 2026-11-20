#!/usr/bin/env bash
# PSScriptAnalyzer (windows/PSScriptAnalyzerSettings.psd1) — windows/*.ps1 에 지적이 하나도 없어야 한다.
# pwsh 가 없으면 건너뛴다(GitHub 러너에는 있다). 모듈은 처음 한 번 사용자 범위로 설치한다.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v pwsh >/dev/null || { echo "test_psscriptanalyzer: pwsh 없음 — 건너뜀"; exit 0; }
check=$(mktemp --suffix=.ps1); trap 'rm -f "$check"' EXIT
cat > "$check" <<'PS'
$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Set-PSRepository PSGallery -InstallationPolicy Trusted
    Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
}
$r = Invoke-ScriptAnalyzer -Path windows -Recurse -Settings windows/PSScriptAnalyzerSettings.psd1
$r | ForEach-Object { Write-Host ("{0}:{1} {2} {3}: {4}" -f $_.ScriptName, $_.Line, $_.Severity, $_.RuleName, $_.Message) }
Write-Host "test_psscriptanalyzer: $($r.Count) finding(s)"
exit [int]($r.Count -gt 0)
PS
pwsh -NoProfile -File "$check"
