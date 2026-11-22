# PowerShell 7 profile, loaded by the Windows Terminal profile that windows\install.ps1 sets up
# (pwsh -NoExit -Command ". ~\.config\powershell\profile.ps1"). Kept out of Documents on purpose:
# Controlled folder access can block writes there.

# Windows Terminal inherits the PATH it started with; re-read it so tools installed since then are found.
$env:Path = (@([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User')) -join ';')
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship.toml'

function Test-Tool($name) { [bool](Get-Command $name -CommandType Application -ErrorAction SilentlyContinue) }

if (Test-Tool starship) { Invoke-Expression (& starship init powershell) }
if (Test-Tool zoxide) { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }

# Built-in aliases (ls, cat, ...) beat functions in command lookup, so drop them before redefining.
Remove-Item Alias:ls, Alias:cat, Alias:cp, Alias:mv, Alias:rm, Alias:man, Alias:diff, Alias:sleep, Alias:ps, Alias:kill -Force -ErrorAction SilentlyContinue

# --- Linux-style commands ---------------------------------------------------------------------------------
if (Test-Tool eza) {
    function ls { eza --icons @args }
    function ll { eza -l --icons --git @args }
    function la { eza -la --icons --git @args }
    function lt { eza --tree --level=2 --icons @args }
} else {
    function ls { Get-ChildItem @args }
    function ll { Get-ChildItem @args | Format-Table Mode, LastWriteTime, Length, Name }
    function la { Get-ChildItem -Force @args }
}
if (Test-Tool bat) { function cat { bat --paging=never @args } } else { function cat { Get-Content @args } }
function which { (Get-Command @args -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
function touch { foreach ($f in $args) { if (Test-Path $f) { (Get-Item $f).LastWriteTime = Get-Date } else { New-Item -ItemType File $f | Out-Null } } }
function head { $n = 10; $a = @($args); if ($a.Count -ge 2 -and $a[0] -eq '-n') { $n = [int]$a[1]; $a = @($a | Select-Object -Skip 2) }; if ($a.Count) { Get-Content $a -TotalCount $n } else { $input | Select-Object -First $n } }
function tail { $n = 10; $follow = $false; $a = @(); for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '-n') { $n = [int]$args[++$i] } elseif ($args[$i] -eq '-f') { $follow = $true } else { $a += $args[$i] } }; if ($a.Count) { Get-Content $a -Tail $n -Wait:$follow } else { $input | Select-Object -Last $n } }
function wc { $a = @($args | Where-Object { $_ -ne '-l' }); if ($a.Count) { @(Get-Content $a).Count } else { @($input).Count } }
function grep { if (Test-Tool rg) { rg @args } else { Select-String @args } }
function find { Get-ChildItem -Recurse -Force -Filter "*$($args[0])*" | ForEach-Object FullName }
function mkdirp { New-Item -ItemType Directory -Force @args | Out-Null }
function cp { Copy-Item -Recurse -Force @args }
function mv { Move-Item -Force @args }
function rmrf { Remove-Item -Recurse -Force @args }
function ln { $a = @($args | Where-Object { $_ -ne '-s' }); New-Item -ItemType SymbolicLink -Path $a[1] -Target $a[0] }
function df { Get-PSDrive -PSProvider FileSystem | Format-Table Name, @{n = 'UsedGB'; e = { [int]($_.Used / 1GB) } }, @{n = 'FreeGB'; e = { [int]($_.Free / 1GB) } } }
function du { Get-ChildItem -Recurse -Force -File @args | Measure-Object Length -Sum | ForEach-Object { '{0:N1} MB' -f ($_.Sum / 1MB) } }
function pkill { Stop-Process -Name @args -Force }
function pgrep { Get-Process -Name "*$($args[0])*" }
function ps { Get-Process @args }
function kill { Stop-Process -Id @args -Force }
function export { param($kv) $k, $v = $kv -split '=', 2; Set-Item "Env:$k" $v }
function sudo { Start-Process pwsh -Verb RunAs -ArgumentList '-NoExit', '-Command', "$args" }
function less { if (Test-Tool bat) { bat @args } else { more @args } }
function open { Invoke-Item @args }
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function lg { lazygit @args }
function g { git @args }
function gs { git status -sb }
function gl { git log --oneline --graph -20 }
function gd { git diff @args }
