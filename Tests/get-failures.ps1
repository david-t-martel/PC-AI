$r = Invoke-Pester -Path '.\Tests\Unit' -PassThru -Output None
Write-Output "=== FAILING TESTS ==="
$r.Failed | ForEach-Object {
    Write-Output "TEST: $($_.Path[-1])"
    Write-Output "ERROR: $($_.ErrorRecord.Exception.Message)"
    Write-Output "---"
}
