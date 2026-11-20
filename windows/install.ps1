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

# Authorized keys: same list as bin/ssh-keys-sync on Linux — the GitHub account's keys plus
# personal\ssh\authorized_keys. Admin accounts use C:\ProgramData\ssh\administrators_authorized_keys.
# Never empties the file: if GitHub can't be reached or returns no keys, nothing changes.
$owner = (git -C $repo remote get-url origin) -replace '.*github\.com[:/]([^/]+)/.*', '$1'
try { $ghKeys = (Invoke-RestMethod -TimeoutSec 20 "https://github.com/$owner.keys") -split "`n" | Where-Object { $_ -match '^(ssh-|ecdsa-|sk-)' } }
catch { $ghKeys = @() }
if ($ghKeys.Count -eq 0) {
    Write-Warning "authorized keys: no keys from github.com/$owner.keys - left unchanged"
} else {
    $extraFile = Join-Path $repo 'personal\ssh\authorized_keys'
    $extra = if (Test-Path $extraFile) { Get-Content $extraFile | Where-Object { $_ -match '^(ssh-|ecdsa-|sk-)' } } else { @() }
    $seen = @{}
    $lines = @("# ssh-keys-sync (install.ps1) manages this file - GitHub($owner) keys + personal/ssh/authorized_keys")
    foreach ($k in @($ghKeys | ForEach-Object { "$($_.Trim()) $owner@github" }) + @($extra)) {
        $id = ($k -split ' ')[0..1] -join ' '
        if (-not $seen[$id]) { $seen[$id] = $true; $lines += $k }
    }
    $isAdmin = (whoami /groups) -match 'S-1-5-32-544'
    $akFile = if ($isAdmin) { 'C:\ProgramData\ssh\administrators_authorized_keys' } else { Join-Path $HOME '.ssh\authorized_keys' }
    $want = ($lines -join "`n") + "`n"
    $have = if (Test-Path $akFile) { [IO.File]::ReadAllText($akFile) -replace '\r\n', "`n" } else { '' }
    if ($want -ne $have) {
        if (Test-Path $akFile) { Copy-Item $akFile "$akFile.bak-dotfiles" -Force }
        [IO.File]::WriteAllText($akFile, $want, (New-Object System.Text.UTF8Encoding($false)))   # keeps the file's ACL
        Write-Host "updated: $akFile ($($lines.Count - 1) keys; previous copy in .bak-dotfiles)"
    }
}
