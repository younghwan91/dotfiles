# Copies windows/bin/* (update, cla, update-windows) into ~\.local\bin, which is on PATH.
# .cmd shims work from cmd, Windows PowerShell 5.1 and pwsh 7, and need no profile
# (profiles live in Documents, which Controlled folder access can lock). Safe to re-run.
#   powershell -File C:\dev\git\dotfiles\windows\install.ps1
$dest = Join-Path $HOME '.local\bin'
New-Item -ItemType Directory -Force $dest | Out-Null
Get-ChildItem (Join-Path $PSScriptRoot 'bin\*') -Include *.cmd, *.ps1 | ForEach-Object {
    Copy-Item $_.FullName $dest -Force
    Write-Host "installed: $dest\$($_.Name)"
}
if (($env:PATH -split ';') -notcontains $dest) { Write-Warning "$dest is not on PATH" }
