# Interactive scripts: they talk to the person at the console, so Write-Host is the point.
# profile.ps1: `starship init` / `zoxide init` print code that has to be Invoke-Expression'd (their documented setup).
@{
    ExcludeRules = @('PSAvoidUsingWriteHost', 'PSAvoidUsingInvokeExpression')
}
