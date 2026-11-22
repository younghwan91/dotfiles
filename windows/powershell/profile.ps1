# PowerShell 7 profile, loaded by the Windows Terminal profile that windows\install.ps1 sets up
# (pwsh -NoExit -Command ". ~\.config\powershell\profile.ps1"). Kept out of Documents on purpose:
# Controlled folder access can block writes there.
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship.toml'
if (Get-Command starship -ErrorAction SilentlyContinue) { Invoke-Expression (& starship init powershell) }
if (Get-Command zoxide -ErrorAction SilentlyContinue) { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }
if (Get-Command bat -ErrorAction SilentlyContinue) { function cat { bat --paging=never @args } }
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ls { eza --icons @args }
    function ll { eza -l --icons --git @args }
}
function lg { lazygit @args }
