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
    # Include goes last, under "Match all", so this PC's own values in ~\.ssh\config win (ssh keeps the first
    # value it reads). An earlier version put it first, which overrode per-PC HostNames. Backed up before editing.
    $cfg = Join-Path $sshDir 'config'
    $old = if (Test-Path $cfg) { [IO.File]::ReadAllText($cfg) } else { '' }
    $body = $old -replace '\r\n', "`n"
    $body = $body -replace '\AInclude config\.d/\*\.conf\n(\n)?', ''
    $body = $body -replace '\n*Match all\nInclude config\.d/\*\.conf\n*\z', ''
    $body = $body.TrimEnd("`n")
    $new = if ($body) { "$body`n`nMatch all`nInclude config.d/*.conf`n" } else { "Match all`nInclude config.d/*.conf`n" }
    if ($new -ne ($old -replace '\r\n', "`n")) {
        if (Test-Path $cfg) { Copy-Item $cfg "$cfg.bak-dotfiles" -Force }
        [IO.File]::WriteAllText($cfg, $new, $utf8)
        Write-Host "updated: $cfg (Include config.d/*.conf last; previous copy in config.bak-dotfiles)"
    }
} else {
    Write-Host "no personal repo at $repo\personal - skipping SSH hosts (clone the private personal repo there to sync them)"
}
