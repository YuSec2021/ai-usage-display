param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$Executable = (Resolve-Path $Executable).Path
New-Item -ItemType Directory -Path $Output -Force | Out-Null
$Output = (Resolve-Path $Output).Path

# Exercise the executable's headless collector before its WinUI entry point.
$collector = Join-Path $Output 'collector.json'
$snapshot = Join-Path $Output 'collector-snapshot.json'
@{
    Snapshot = $snapshot
    Settings = (Join-Path $Output 'unused-settings.json')
    InstalledCommand = 'isolated fixture'
    OriginalStatusLine = $null
} | ConvertTo-Json | Set-Content -Encoding utf8 $collector
$start = [System.Diagnostics.ProcessStartInfo]::new($Executable)
$start.UseShellExecute = $false
$start.RedirectStandardInput = $true
$start.RedirectStandardError = $true
$start.CreateNoWindow = $true
$start.ArgumentList.Add('--claude-statusline')
$start.ArgumentList.Add($collector)
$process = [System.Diagnostics.Process]::Start($start)
$inputData = @{ prompt = 'private-fixture'; api_key = 'secret-fixture'; rate_limits = @{
    five_hour = @{ used_percentage = 0; resets_at = [DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds() }
} } | ConvertTo-Json -Depth 5 -Compress
$process.StandardInput.Write($inputData)
$process.StandardInput.Close()
if (-not $process.WaitForExit(15000)) { $process.Kill($true); throw 'Collector timed out' }
if ($process.ExitCode -ne 0) { throw "Collector failed with exit code $($process.ExitCode)" }
$sanitized = Get-Content -Raw $snapshot
if ($sanitized -match 'private-fixture|secret-fixture|api_key|prompt') { throw 'Collector persisted forbidden fields' }
if (($sanitized | ConvertFrom-Json).rate_limits.five_hour.used_percentage -ne 0) { throw 'Collector lost genuine zero usage' }

$start = [System.Diagnostics.ProcessStartInfo]::new($Executable)
$start.UseShellExecute = $false
$start.ArgumentList.Add('--smoke-test')
$start.ArgumentList.Add($Output)
$process = [System.Diagnostics.Process]::Start($start)
if (-not $process.WaitForExit(60000)) { $process.Kill($true); throw 'Native WinUI smoke test timed out' }
if ($process.ExitCode -ne 0) {
    $errorFile = Join-Path $Output 'smoke-error.json'
    if (Test-Path $errorFile) { Get-Content -Raw $errorFile | Write-Output }
    $progressFile = Join-Path $Output 'smoke-progress.json'
    if (Test-Path $progressFile) { Get-Content -Raw $progressFile | Write-Output }
    $exceptionsFile = Join-Path $Output 'smoke-exceptions.txt'
    if (Test-Path $exceptionsFile) { Get-Content -Raw $exceptionsFile | Write-Output }
    Start-Sleep -Seconds 2
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddMinutes(-2); Level = 2 } -ErrorAction SilentlyContinue |
        Select-Object -First 4 TimeCreated, ProviderName, Message | Format-List | Out-String | Write-Output
    $cdb = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/Debuggers/x64/cdb.exe'
    if ($env:CI -eq 'true' -and (Test-Path $cdb)) {
        $debugStart = [System.Diagnostics.ProcessStartInfo]::new($cdb)
        $debugStart.UseShellExecute = $false
        $debugStart.RedirectStandardOutput = $true
        foreach ($argument in @('-o', '-g', '-G', '-c', '.symfix; sxe -c ".exr -1;kb;!analyze -v;q" 0xc000027b;g', $Executable, '--smoke-test', $Output)) {
            $debugStart.ArgumentList.Add($argument)
        }
        $debugger = [System.Diagnostics.Process]::Start($debugStart)
        $debugOutput = $debugger.StandardOutput.ReadToEndAsync()
        if (-not $debugger.WaitForExit(120000)) { $debugger.Kill($true); $debugger.WaitForExit(5000) | Out-Null }
        if ($debugOutput.Wait(5000)) {
            $debugOutput.Result | Set-Content (Join-Path $Output 'native-debugger.txt')
            $debugOutput.Result | Write-Output
        }
    }
    throw "Native smoke test failed with exit code $($process.ExitCode)"
}
$result = Get-Content -Raw (Join-Path $Output 'smoke.json') | ConvertFrom-Json
if (-not $result.success -or $result.trayIcons -ne 4 -or -not $result.noFloatingPercentages) { throw 'Native smoke assertions failed' }
$result | ConvertTo-Json
