# Installs Windows Update *software* updates with the built-in Windows Update Agent API (no modules).
# Drivers and firmware (UpdateType 2) are listed but skipped: they can hit hardware, so install those by hand.
# Called by update.cmd (-NoPause, already elevated). Run on its own it relaunches itself elevated (one UAC prompt).
param([switch]$NoPause)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process pwsh -Verb RunAs -Wait -ArgumentList '-NoProfile', '-File', "`"$PSCommandPath`""
    return
}

try {
    $session = New-Object -ComObject Microsoft.Update.Session
    Write-Host 'Windows Update: searching...'
    $found = $session.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0').Updates
    if ($found.Count -eq 0) { Write-Host 'Windows Update: up to date.'; return }

    $todo = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $found) {
        if ($u.Type -eq 2) { Write-Host "  - (skipped, driver/firmware) $($u.Title)"; continue }
        Write-Host "  - $($u.Title)"
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        [void]$todo.Add($u)
    }
    if ($todo.Count -eq 0) { Write-Host 'Windows Update: nothing to install except drivers (Settings > Windows Update > Advanced options > Optional updates).'; return }

    Write-Host 'Windows Update: downloading...'
    $dl = $session.CreateUpdateDownloader(); $dl.Updates = $todo; [void]$dl.Download()

    $ready = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $todo) { if ($u.IsDownloaded) { [void]$ready.Add($u) } }

    Write-Host 'Windows Update: installing...'
    $inst = $session.CreateUpdateInstaller(); $inst.Updates = $ready
    $res = $inst.Install()
    Write-Host "Windows Update: done (result $($res.ResultCode))."
    if ($res.RebootRequired) { Write-Host 'Reboot required to finish.' }
} catch {
    Write-Host "Windows Update failed: $($_.Exception.Message)"
} finally {
    if (-not $NoPause) { Read-Host 'Press Enter to close' }
}
