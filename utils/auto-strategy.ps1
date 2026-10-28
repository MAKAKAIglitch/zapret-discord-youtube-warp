$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$utilsDir = Join-Path $root 'utils'
$listsDir = Join-Path $root 'lists'
$settingsFile = Join-Path $utilsDir 'fix_filters.ini'
$logFile = Join-Path $utilsDir 'auto-strategy.log'
$lastRunFile = Join-Path $utilsDir 'auto-strategy.last-run.txt'
$lockFile = Join-Path $utilsDir 'auto-strategy.lock'
$serviceBat = Join-Path $root 'service.bat'
$winwsExe = Join-Path $root 'bin\winws.exe'
$hostlistFile = Join-Path $listsDir 'hostlist-auto.txt'
$hostlistBackup = Join-Path $env:TEMP ('zapret-hostlist-auto-' + [guid]::NewGuid().ToString('N') + '.txt')
$serviceStopped = $false
$lockAcquired = $false
$hostlistExisted = Test-Path -LiteralPath $hostlistFile
$serviceStrategyToRestore = $null
$completedNormally = $false
$hostlistBackupMade = $false
$originalStrategy = $null
$launcher = $null

$env:NO_UPDATE_CHECK = '1'

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    if (Test-Path -LiteralPath $logFile) {
        $info = Get-Item -LiteralPath $logFile
        if ($info.Length -gt 1MB) {
            $tail = Get-Content -LiteralPath $logFile -Tail 500
            Set-Content -LiteralPath $logFile -Value $tail -Encoding UTF8
        }
    }
}

function Read-FixSettings {
    $settings = @{ autostrategy = '0'; autohostlist = '0' }
    if (Test-Path -LiteralPath $settingsFile) {
        foreach ($line in Get-Content -LiteralPath $settingsFile) {
            if ($line -match '^\s*([^=]+?)\s*=\s*(.*?)\s*$') {
                $settings[$matches[1].ToLowerInvariant()] = $matches[2]
            }
        }
    }
    return $settings
}

function Get-UserIdleSeconds {
    if (-not ('ZapretIdle.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace ZapretIdle {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public UInt32 cbSize;
        public UInt32 dwTime;
    }
    public static class NativeMethods {
        [DllImport("user32.dll")]
        public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    }
}
'@
    }

    $info = New-Object ZapretIdle.LASTINPUTINFO
    $info.cbSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf([type][ZapretIdle.LASTINPUTINFO])
    if (-not [ZapretIdle.NativeMethods]::GetLastInputInfo([ref]$info)) {
        return 0
    }

    $now = [int64][Environment]::TickCount
    if ($now -lt 0) { $now += 4294967296 }
    $last = [int64]$info.dwTime
    $idleMs = $now - $last
    if ($idleMs -lt 0) { $idleMs += 4294967296 }
    return [int][Math]::Floor($idleMs / 1000)
}

function Get-NetworkByteTotal {
    $total = [int64]0
    foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up -or
            $adapter.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) {
            continue
        }
        try {
            $stats = $adapter.GetIPStatistics()
            $total += [int64]$stats.BytesReceived + [int64]$stats.BytesSent
        } catch {
            # Some virtual adapters do not expose statistics.
        }
    }
    return $total
}

function Test-IdleEnough {
    param([switch]$CheckNetwork)
    $idleSeconds = Get-UserIdleSeconds
    if ($idleSeconds -lt 900) {
        Write-Log ("Skipped: user idle time is only {0}s (need 900s)." -f $idleSeconds)
        return $false
    }

    if ($CheckNetwork) {
        $before = Get-NetworkByteTotal
        Start-Sleep -Seconds 20
        $after = Get-NetworkByteTotal
        $delta = if ($after -ge $before) { $after - $before } else { 0 }
        if ($delta -gt 2MB) {
            Write-Log ("Skipped: network was active during idle check ({0:N0} bytes in 20 seconds)." -f $delta)
            return $false
        }
        if ((Get-UserIdleSeconds) -lt 900) {
            Write-Log 'Skipped: user activity resumed during network idle check.'
            return $false
        }
    }
    return $true
}

function Restore-HostlistSnapshot {
    try {
        if ($hostlistBackupMade -and (Test-Path -LiteralPath $hostlistBackup)) {
            Copy-Item -LiteralPath $hostlistBackup -Destination $hostlistFile -Force
        } elseif (-not $hostlistExisted) {
            Remove-Item -LiteralPath $hostlistFile -Force -ErrorAction SilentlyContinue
        }
    } catch {
        try { Write-Log "Could not restore autohostlist snapshot: $($_.Exception.Message)" } catch {}
    }
}

function Stop-CandidateWinws {
    # The worker refuses to start if any unrelated winws instance is present.
    try {
        $processes = @(Get-CimInstance Win32_Process -Filter "Name='winws.exe'" -ErrorAction SilentlyContinue)
        foreach ($process in $processes) {
            if ($process.ExecutablePath -and
                [string]::Equals($process.ExecutablePath, $winwsExe, [StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}
    if ($script:launcher -and -not $script:launcher.HasExited) {
        Stop-Process -Id $script:launcher.Id -Force -ErrorAction SilentlyContinue
    }
    $script:launcher = $null
}

function Invoke-ServiceStrategyInstall {
    param([string]$StrategyName)

    if (-not $StrategyName -or $StrategyName -notmatch '^general.*\.bat$') {
        Write-Log "Refusing invalid strategy name: '$StrategyName'."
        return $false
    }

    $captureFile = Join-Path $env:TEMP ('zapret-auto-install-' + [guid]::NewGuid().ToString('N') + '.log')
    $command = '"' + $serviceBat + '" install_strategy_auto "' + $StrategyName + '" admin > "' + $captureFile + '" 2>&1'
    $cmdArgs = '/d /s /c "' + $command + '"'
    try {
        $proc = Start-Process -FilePath $env:ComSpec -ArgumentList $cmdArgs -WorkingDirectory $root -PassThru -Wait -WindowStyle Hidden
        if (Test-Path -LiteralPath $captureFile) {
            Get-Content -LiteralPath $captureFile -ErrorAction SilentlyContinue | ForEach-Object { Write-Log $_ }
        }
        $service = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
        $ok = ($proc.ExitCode -eq 0 -and $service -and $service.Status -eq 'Running')
        if ($ok) {
            Write-Log "Installed and started strategy '$StrategyName'."
        } else {
            Write-Log "Failed to install/start strategy '$StrategyName' (exit=$($proc.ExitCode), state=$($service.Status))."
        }
        return [bool]$ok
    } catch {
        Write-Log "Exception while installing '$StrategyName': $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -LiteralPath $captureFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-UrlChecks {
    param([string[]]$Urls)

    $worker = {
        param([string]$Url)
        $code = 0
        $httpCode = '000'
        $timeSeconds = 99.0
        try {
            $response = & curl.exe -I -sS --max-time 4 --connect-timeout 2 -o NUL -w '%{http_code}|%{time_total}' $Url 2>$null
            $code = $LASTEXITCODE
            $text = ($response | Out-String).Trim()
            if ($text -match '^(?<status>\d{3})\|(?<seconds>\d+(?:\.\d+)?)$') {
                $httpCode = $matches['status']
                $timeSeconds = [double]::Parse($matches['seconds'], [Globalization.CultureInfo]::InvariantCulture)
            }
        } catch {
            $code = 1
        }
        $statusNumber = 0
        [void][int]::TryParse($httpCode, [ref]$statusNumber)
        return [PSCustomObject]@{
            Url = $Url
            Success = ($code -eq 0 -and $statusNumber -ge 100 -and $statusNumber -le 599)
            HttpCode = $httpCode
            TimeSeconds = $timeSeconds
        }
    }

    $poolSize = [Math]::Min(8, $Urls.Count)
    $pool = [runspacefactory]::CreateRunspacePool(1, [Math]::Max(1, $poolSize))
    $pool.Open()
    $jobs = @()
    try {
        foreach ($url in $Urls) {
            $ps = [powershell]::Create().AddScript($worker).AddArgument($url)
            $ps.RunspacePool = $pool
            $jobs += [PSCustomObject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke() }
        }

        $results = @()
        foreach ($job in $jobs) {
            try {
                if (-not $job.Handle.AsyncWaitHandle.WaitOne(10000)) {
                    try { $job.PowerShell.Stop() } catch {}
                }
                $result = $job.PowerShell.EndInvoke($job.Handle)
                if ($result) { $results += $result }
            } catch {
                $results += [PSCustomObject]@{ Url = ''; Success = $false; HttpCode = 'ERR'; TimeSeconds = 99.0 }
            } finally {
                $job.PowerShell.Dispose()
            }
        }
        $ok = @($results | Where-Object { $_.Success })
        $avg = if ($ok.Count -gt 0) {
            ($ok | Measure-Object -Property TimeSeconds -Average).Average
        } else {
            99.0
        }
        return [PSCustomObject]@{
            Score = $ok.Count
            AverageSeconds = [double]$avg
            Results = $results
        }
    } finally {
        foreach ($job in $jobs) { try { $job.PowerShell.Dispose() } catch {} }
        $pool.Close()
        $pool.Dispose()
    }
}

# Skip entirely unless the option is explicitly enabled.
$settings = Read-FixSettings
if ($settings['autostrategy'] -ne '1') { return }

if (Test-Path -LiteralPath $lastRunFile) {
    try {
        $lastRun = [datetime]::Parse((Get-Content -LiteralPath $lastRunFile -Raw).Trim())
        if ((Get-Date) - $lastRun -lt [TimeSpan]::FromHours(6)) {
            return
        }
    } catch {}
}

if (Test-Path -LiteralPath $lockFile) {
    $lockInfo = Get-Item -LiteralPath $lockFile
    if ($lockInfo.LastWriteTime -gt (Get-Date).AddHours(-3)) { return }
    Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
}

try {
    New-Item -ItemType File -Path $lockFile -ErrorAction Stop | Out-Null
    $lockAcquired = $true
} catch {
    return
}

try {
    if (-not (Test-Path -LiteralPath $serviceBat) -or -not (Test-Path -LiteralPath $winwsExe)) {
        Write-Log 'Skipped: service.bat or bin\winws.exe is missing.'
        return
    }
    if (-not (Test-IdleEnough -CheckNetwork)) { return }

    $service = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -ne 'Running') {
        Write-Log 'Skipped: zapret service is not running.'
        return
    }

    $registry = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\zapret' -ErrorAction SilentlyContinue
    $originalStrategy = [string]$registry.'zapret-discord-youtube'
    if (-not $originalStrategy -or -not (Test-Path -LiteralPath (Join-Path $root ($originalStrategy + '.bat')))) {
        Write-Log 'Skipped: could not identify the currently installed strategy.'
        return
    }
    $serviceStrategyToRestore = $originalStrategy

    # Do not interfere with multiple/foreign winws instances or a manual test run.
    if (Test-Path -LiteralPath (Join-Path $root 'utils\ipset_switched.flag')) {
        Write-Log 'Skipped: another strategy test has switched the IPSet list.'
        return
    }
    $runningWinws = @(Get-CimInstance Win32_Process -Filter "Name='winws.exe'" -ErrorAction SilentlyContinue)
    if ($runningWinws.Count -ne 1 -or
        -not [string]::Equals($runningWinws[0].ExecutablePath, $winwsExe, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Log "Skipped: expected exactly one zapret winws instance; found $($runningWinws.Count)."
        return
    }

    if ($hostlistExisted) {
        Copy-Item -LiteralPath $hostlistFile -Destination $hostlistBackup -Force
        $hostlistBackupMade = $true
    }

    $targetsFile = Join-Path $utilsDir 'targets.txt'
    $urls = @()
    if (Test-Path -LiteralPath $targetsFile) {
        foreach ($line in Get-Content -LiteralPath $targetsFile) {
            if ($line -match '^\s*\w+\s*=\s*"(https?://[^"]+)"\s*$') {
                $urls += $matches[1]
            }
        }
    }
    $urls = @($urls | Select-Object -Unique)
    if ($urls.Count -eq 0) {
        Write-Log 'Skipped: no HTTP/HTTPS targets in utils\targets.txt.'
        return
    }

    $candidates = @(Get-ChildItem -LiteralPath $root -Filter 'general*.bat' -File |
        Sort-Object { [Regex]::Replace($_.Name, '(\d+)', { $args[0].Value.PadLeft(8, '0') }) })
    if ($candidates.Count -eq 0) {
        Write-Log 'Skipped: no general*.bat strategies found.'
        return
    }

    Write-Log "Idle auto-pick started; current strategy=$originalStrategy; candidates=$($candidates.Count); URLs=$($urls.Count)."
    Stop-Service -Name 'zapret' -Force
    $serviceStopped = $true
    (Get-Service -Name 'zapret').WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))

    $stopDeadline = (Get-Date).AddSeconds(10)
    do {
        $left = @(Get-CimInstance Win32_Process -Filter "Name='winws.exe'" -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $stopDeadline)
    if ($left.Count -gt 0) {
        throw 'The installed winws process did not exit after stopping the service.'
    }

    $results = @()
    $aborted = $false
    foreach ($config in $candidates) {
        if (-not (Test-IdleEnough -CheckNetwork)) {
            Write-Log 'User activity or network activity detected; stopping automatic tests and restoring the original strategy.'
            $aborted = $true
            break
        }

        Restore-HostlistSnapshot
        Write-Log "Testing $($config.Name)..."
        $cmdArgs = '/d /s /c ""' + $config.FullName + '""'
        $script:launcher = Start-Process -FilePath $env:ComSpec -ArgumentList $cmdArgs -WorkingDirectory $root -PassThru -WindowStyle Hidden

        $ready = $false
        $readyDeadline = (Get-Date).AddSeconds(8)
        do {
            $candidateProcesses = @(Get-CimInstance Win32_Process -Filter "Name='winws.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.ExecutablePath -and [string]::Equals($_.ExecutablePath, $winwsExe, [StringComparison]::OrdinalIgnoreCase) })
            if ($candidateProcesses.Count -eq 1) { $ready = $true; break }
            Start-Sleep -Milliseconds 250
        } while ((Get-Date) -lt $readyDeadline)

        if ($ready) {
            $scores = Invoke-UrlChecks -Urls $urls
            $results += [PSCustomObject]@{
                Strategy = $config.BaseName
                Score = $scores.Score
                AverageSeconds = $scores.AverageSeconds
            }
            Write-Log ("{0}: {1}/{2} URLs reachable; mean successful response {3:N2}s." -f $config.BaseName, $scores.Score, $urls.Count, $scores.AverageSeconds)
        } else {
            $results += [PSCustomObject]@{
                Strategy = $config.BaseName
                Score = 0
                AverageSeconds = 99.0
            }
            Write-Log "$($config.Name) failed to start winws; score=0."
        }

        Stop-CandidateWinws
        if (-not (Test-IdleEnough -CheckNetwork)) {
            Write-Log 'User activity or network activity detected after a strategy test; restoring the original strategy.'
            $aborted = $true
            break
        }
    }

    if (-not $aborted -and $results.Count -gt 0) {
        $best = $results | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'AverageSeconds'; Descending = $false } | Select-Object -First 1
        $current = $results | Where-Object { $_.Strategy -ieq $originalStrategy } | Select-Object -First 1

        if ($best.Score -lt 3) {
            Write-Log "No strategy passed the minimum reliability threshold (best score $($best.Score)); keeping $originalStrategy."
        } elseif ($current -and $best.Score -ge ($current.Score + 2)) {
            $serviceStrategyToRestore = $best.Strategy
            Write-Log "Selected $($best.Strategy): score $($best.Score), current $originalStrategy scored $($current.Score)."
        } else {
            Write-Log "No material improvement found; keeping $originalStrategy (best score $($best.Score))."
        }
        $completedNormally = $true
    }
}
catch {
    Write-Log "Auto-pick error: $($_.Exception.Message)"
}
finally {
    Stop-CandidateWinws
    Restore-HostlistSnapshot

    if ($serviceStopped -and $originalStrategy) {
        $desired = if ($serviceStrategyToRestore) { $serviceStrategyToRestore } else { $originalStrategy }
        $installed = Invoke-ServiceStrategyInstall -StrategyName ($desired + '.bat')
        if (-not $installed -and $desired -ne $originalStrategy) {
            Write-Log 'Chosen strategy failed to install; attempting to restore the original strategy.'
            $installed = Invoke-ServiceStrategyInstall -StrategyName ($originalStrategy + '.bat')
        }
        if (-not $installed) {
            Write-Log 'CRITICAL: the strategy service could not be restored automatically.'
        }
    }

    if ($completedNormally) {
        (Get-Date).ToString('o') | Set-Content -LiteralPath $lastRunFile -Encoding ASCII
    }
    Remove-Item -LiteralPath $hostlistBackup -Force -ErrorAction SilentlyContinue
    if ($lockAcquired) { Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue }
}
