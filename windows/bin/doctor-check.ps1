# Checks this PC for problems that keep coming back. Read-only: it reports and prints the fix, changes nothing.
$ok = $true

$svc = Get-Service WSLService -ErrorAction SilentlyContinue
if ($svc -and $svc.StartType -eq 'Disabled') {
    $ok = $false
    Write-Host '[!] WSLService is Disabled (AhnLab Safe Transaction does this on boot/wake; WSL fails with 0x80070422)'
    Write-Host '    fix (admin): Set-Service -Name WSLService -StartupType Manual; Start-Service WSLService'
}

$key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
if (Test-Path $key) {
    $props = Get-ItemProperty $key
    $off = $props.PSObject.Properties | Where-Object { $_.Value -is [byte[]] -and $_.Value[0] -band 1 } | Where-Object { $_.Name -match 'Kakao|Google ?Drive' } | Select-Object -ExpandProperty Name
    if ($off) {
        $ok = $false
        Write-Host "[!] KakaoTalk/Google Drive startup disabled (CCleaner Health Check does this): $($off -join ', ')"
        Write-Host '    fix: re-enable in Task Manager > Startup apps, then turn off CCleaner Health Check / its service'
    }
}

if ($ok) { Write-Host 'doctor: nothing wrong found.' }
