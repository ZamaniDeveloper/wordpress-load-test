Write-Warning "run-webava-light.ps1 is deprecated; use run-load-test.ps1 instead."
& "$PSScriptRoot\run-load-test.ps1"
exit $LASTEXITCODE
