# Keeps asking Oracle for the Always Free Ampere server until Mumbai has room.
#
# It applies the Resource Manager stack saved from the Create instance form
# ("portfolio-stack"), so the shape, image, network and SSH key all come from
# that form. A capacity error means "try again later": it waits and retries.
# Any other error stops the script, so it never loops on a real problem.
#
# Usage, from PowerShell:
#   .\retry-a1.ps1 -StackId ocid1.ormstack.oc1.ap-mumbai-1.xxxxx
#   .\retry-a1.ps1 -StackId ocid1... -Minutes 10     # wait longer between tries
#
# Needs Oracle's CLI (installed in %USERPROFILE%\oci-cli) and an API key in
# %USERPROFILE%\.oci\config.

param(
    [Parameter(Mandatory = $true)][string]$StackId,
    [int]$Minutes = 5
)

$oci = Join-Path $env:USERPROFILE "oci-cli\Scripts\oci.exe"
$log = Join-Path $PSScriptRoot "retry-a1.log"
$errFile = Join-Path $env:TEMP "retry-a1.stderr.txt"
$env:OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING = "True"

function Say($text) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $text
    Write-Host $line
    Add-Content -Path $log -Value $line
}

if (-not (Test-Path $oci)) { throw "Oracle CLI not found at $oci" }

$try = 0
while ($true) {
    $try++
    Say "Try ${try}: applying the stack..."
    $out = & $oci resource-manager job create-apply-job `
        --stack-id $StackId `
        --execution-plan-strategy AUTO_APPROVED `
        --wait-for-state SUCCEEDED --wait-for-state FAILED --wait-for-state CANCELED `
        --max-wait-seconds 1200 2> $errFile
    # The CLI prints progress ("Action completed. Waiting...") on stderr and
    # the job as JSON on stdout; only stdout is parsed.
    $text = ($out | Out-String)
    try { $job = $text | ConvertFrom-Json } catch { $job = $null }

    if (-not $job) {
        Say "The CLI call itself failed, so stopping. Its output:"
        Say ($text + (Get-Content $errFile -Raw -ErrorAction SilentlyContinue)).Trim()
        exit 1
    }

    $state = $job.data.'lifecycle-state'
    $jobId = $job.data.id
    if ($state -eq "SUCCEEDED") {
        Say "SUCCESS: the Ampere server was created. Open Compute > Instances for its public IP."
        1..3 | ForEach-Object { [console]::Beep(880, 300); Start-Sleep -Milliseconds 150 }
        exit 0
    }

    # Read the job's log to see why it failed.
    $logs = (& $oci resource-manager job get-job-logs --job-id $jobId --all 2> $errFile | Out-String)
    if ($logs -match "Out of (host )?capacity") {
        Say "Out of capacity in Mumbai. Waiting $Minutes minutes."
        Start-Sleep -Seconds ($Minutes * 60)
        continue
    }
    if ($logs -match "TooManyRequests|429") {
        Say "Oracle asked us to slow down. Waiting $([Math]::Max($Minutes * 3, 15)) minutes."
        Start-Sleep -Seconds ([Math]::Max($Minutes * 3, 15) * 60)
        continue
    }

    Say "The job ended as $state for a reason other than capacity, so stopping."
    Say "Job: $jobId (Resource Manager > Stacks > portfolio-stack > Jobs shows its log)."
    $logs -split "`n" | Where-Object { $_ -match '"message"' } | Select-Object -Last 8 | ForEach-Object { Say $_.Trim() }
    exit 1
}
