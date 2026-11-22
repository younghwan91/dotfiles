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

# Authorized keys: same list as bin/ssh-keys-sync on Linux - the GitHub account's keys plus
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

# Daily sync, like the Linux crons: pull dotfiles (+ personal) and re-run this script at 09:30, so SSH hosts and
# authorized keys follow the repos without anyone remembering. Needs an elevated session to register (the keys
# file is admin-only); re-running just updates the task.
$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isElevated) {
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }
    $cmd = "git -C '$repo' pull -q --ff-only; if (Test-Path '$repo\personal') { git -C '$repo\personal' pull -q --ff-only }; & '$repo\windows\install.ps1'"
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$cmd`""
    $trigger = New-ScheduledTaskTrigger -Daily -At 9:30am
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
    Register-ScheduledTask -TaskName 'dotfiles-sync' -Action $action -Trigger $trigger -Settings $settings `
        -User $env:USERNAME -RunLevel Highest -Force | Out-Null
    Write-Host "scheduled: dotfiles-sync daily 09:30 (git pull + install.ps1)"
} else {
    Write-Host "not elevated - skipped the daily dotfiles-sync task (run install.ps1 as admin once to add it)"
}

# Claude Code: the same global rules as the Linux PCs (install.sh --claude-md links them there). Copied, not
# linked; the daily dotfiles-sync task keeps the copies current.
$claudeDir = Join-Path $HOME '.claude'
New-Item -ItemType Directory -Force $claudeDir | Out-Null
$pairs = @(@((Join-Path $repo 'claude\CLAUDE.md'), (Join-Path $claudeDir 'CLAUDE.md')),
           @((Join-Path $repo 'personal\claude\CLAUDE.md'), (Join-Path $claudeDir 'CLAUDE.personal.md')))
foreach ($p in $pairs) {
    if (-not (Test-Path $p[0])) { continue }
    $src = [IO.File]::ReadAllText($p[0]); $dst = if (Test-Path $p[1]) { [IO.File]::ReadAllText($p[1]) } else { $null }
    if ($src -ne $dst) {
        if ($null -ne $dst -and -not (Test-Path "$($p[1]).bak")) { Copy-Item $p[1] "$($p[1]).bak" }
        [IO.File]::WriteAllText($p[1], $src, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "installed: $($p[1])"
    }
}

# Terminal look: Shades of Purple + JetBrains Mono in Windows Terminal, Starship prompt and a small pwsh profile.
# The profile is loaded by the Windows Terminal "PowerShell 7" entry (not from Documents, which Controlled folder
# access can lock), so plain pwsh outside Windows Terminal stays untouched.
$cfgDir = Join-Path $HOME '.config'
New-Item -ItemType Directory -Force (Join-Path $cfgDir 'powershell') | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'starship.toml') (Join-Path $cfgDir 'starship.toml') -Force
Copy-Item (Join-Path $PSScriptRoot 'powershell\profile.ps1') (Join-Path $cfgDir 'powershell\profile.ps1') -Force
Write-Host "installed: $cfgDir\starship.toml, $cfgDir\powershell\profile.ps1"

$wt = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (Test-Path $wt) {
    $look = Get-Content (Join-Path $PSScriptRoot 'terminal\shades-of-purple.json') -Raw | ConvertFrom-Json
    $s = Get-Content $wt -Raw | ConvertFrom-Json
    $s.schemes = @(@($s.schemes) | Where-Object { $_.name -ne $look.scheme.name }) + $look.scheme
    $def = $s.profiles.defaults
    $def | Add-Member -NotePropertyName colorScheme -NotePropertyValue $look.scheme.name -Force
    $def | Add-Member -NotePropertyName font -NotePropertyValue $look.font -Force
    $pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    foreach ($p in $s.profiles.list | Where-Object { $_.name -eq 'PowerShell 7' -and $pwshExe }) {
        $p | Add-Member -NotePropertyName commandline -NotePropertyValue "`"$pwshExe`" -NoLogo -NoExit -Command `". '$cfgDir\powershell\profile.ps1'`"" -Force
    }
    $pw7 = $s.profiles.list | Where-Object { $_.name -eq 'PowerShell 7' } | Select-Object -First 1
    if ($pw7 -and $pwshExe) { $s.defaultProfile = $pw7.guid }
    # One shell in the menu: PowerShell 7 (+ WSL distros). cmd and Windows PowerShell 5.1 stay installed, just hidden.
    foreach ($p in $s.profiles.list) { $p | Add-Member -NotePropertyName hidden -NotePropertyValue (-not ($p.name -eq 'PowerShell 7' -or $p.name -like 'Ubuntu*')) -Force }
    $json = $s | ConvertTo-Json -Depth 20
    if ($json -ne (Get-Content $wt -Raw).TrimEnd()) {
        Copy-Item $wt "$wt.bak-dotfiles" -Force
        [IO.File]::WriteAllText($wt, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "updated: Windows Terminal settings (previous copy in settings.json.bak-dotfiles)"
    }
}

# Orca: the same theme as a custom terminal theme. Orca rewrites its settings on exit, so only touch the file
# while Orca is closed; the daily run picks it up later otherwise.
$orcaData = Join-Path $env:APPDATA 'orca\orca-data.json'
if ((Test-Path $orcaData) -and -not (Get-Process -Name orca -ErrorAction SilentlyContinue)) {
    $theme = Get-Content (Join-Path $PSScriptRoot 'orca\shades-of-purple.json') -Raw | ConvertFrom-Json
    $o = Get-Content $orcaData -Raw | ConvertFrom-Json
    $o.settings.terminalCustomThemes = @(@($o.settings.terminalCustomThemes) | Where-Object { $_.id -ne $theme.id }) + $theme
    $o.settings.terminalThemeDark = "custom:$($theme.id)"
    $o.settings.terminalFontFamily = 'JetBrainsMono NFM'
    $oj = $o | ConvertTo-Json -Depth 100
    if ($oj -ne (Get-Content $orcaData -Raw).TrimEnd()) {
        Copy-Item $orcaData "$orcaData.bak-dotfiles" -Force
        [IO.File]::WriteAllText($orcaData, $oj, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "updated: Orca terminal theme"
    }
}
