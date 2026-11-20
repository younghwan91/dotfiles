# Copies windows/bin/* (update, cla, update-windows) into ~\.local\bin, which is on PATH, and syncs SSH hosts from personal\.
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

# SSH: the shared host list from the private personal repo (cloned at <repo>\personal), same layout as
# install.sh on Linux: ~\.ssh\config.d\dotfiles-personal.conf + "Include config.d/*.conf" at the top of
# ~\.ssh\config. Copied, not linked (symlinks need admin). Written without a BOM: OpenSSH rejects one.
$repo = Split-Path $PSScriptRoot -Parent
$shared = Join-Path $repo 'personal\ssh\config'
if (Test-Path $shared) {
    $sshDir = Join-Path $HOME '.ssh'
    $confD = Join-Path $sshDir 'config.d'
    New-Item -ItemType Directory -Force $confD | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $confD 'dotfiles-personal.conf'), [IO.File]::ReadAllText($shared), $utf8)
    Write-Host "installed: $confD\dotfiles-personal.conf"
    $cfg = Join-Path $sshDir 'config'
    $old = if (Test-Path $cfg) { [IO.File]::ReadAllText($cfg) } else { '' }
    if ($old -notmatch '(?m)^Include config\.d/\*\.conf\s*$') {
        [IO.File]::WriteAllText($cfg, "Include config.d/*.conf`n`n" + $old, $utf8)
        Write-Host "updated: $cfg (Include config.d/*.conf)"
    }
} else {
    Write-Host "no personal repo at $repo\personal - skipping SSH hosts (clone the private personal repo there to sync them)"
}
