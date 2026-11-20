# New Windows PC: install the apps in winget-packages.json, then link the shims.
#   pwsh -File C:\dev\git\dotfiles\windows\setup.ps1
# Refresh the list from this PC with: winget export -o windows\winget-packages.json
# (then drop runtimes/frameworks - they come in as dependencies).
winget import -i (Join-Path $PSScriptRoot 'winget-packages.json') --accept-package-agreements --accept-source-agreements --ignore-unavailable
& (Join-Path $PSScriptRoot 'install.ps1')
