param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Enable', 'Disable')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$taskName = 'Zapret Auto Strategy'

try {
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    $folder = $scheduler.GetFolder('\')

    if ($Action -eq 'Disable') {
        try {
            $folder.DeleteTask($taskName, 0)
        } catch {
            # A missing task is already the desired disabled state.
        }
        exit 0
    }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principalObject = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principalObject.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run service.bat as administrator to register the scheduled task.'
    }

    $service = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -ne 'Running') {
        throw 'Start the zapret service before enabling automatic strategy selection.'
    }

    $userId = $identity.Name
    if ([string]::IsNullOrWhiteSpace($userId) -or $userId -match '^(NT AUTHORITY|NT SERVICE)\\') {
        throw 'Auto strategy requires a regular interactive Windows account.'
    }

    $root = Split-Path -Parent $PSScriptRoot
    $worker = Join-Path $PSScriptRoot 'auto-strategy.ps1'
    if (-not (Test-Path -LiteralPath $worker)) {
        throw "Worker script not found: $worker"
    }

    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $definition = $scheduler.NewTask(0)
    $definition.RegistrationInfo.Description = 'Optionally tests zapret strategies only while the signed-in user and network are idle.'
    $definition.Settings.Enabled = $true
    $definition.Settings.Hidden = $false
    $definition.Settings.StartWhenAvailable = $true
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.MultipleInstances = 2
    $definition.Settings.ExecutionTimeLimit = 'PT3H'

    # A daily trigger with a repeating interval covers the whole day; the worker
    # itself checks input inactivity and network traffic before touching zapret.
    $trigger = $definition.Triggers.Create(2) # TASK_TRIGGER_DAILY
    $firstRun = (Get-Date).AddMinutes(2)
    $trigger.StartBoundary = $firstRun.ToString("yyyy-MM-dd'T'HH:mm:ss")
    $trigger.DaysInterval = 1
    $trigger.Repetition.Interval = 'PT30M'
    $trigger.Repetition.Duration = 'P1D'
    $trigger.Repetition.StopAtDurationEnd = $false

    $actionDefinition = $definition.Actions.Create(0) # TASK_ACTION_EXEC
    $actionDefinition.Path = $powerShellPath
    $actionDefinition.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $worker + '"'
    $actionDefinition.WorkingDirectory = $root

    $definition.Principal.UserId = $userId
    $definition.Principal.LogonType = 3 # TASK_LOGON_INTERACTIVE_TOKEN
    $definition.Principal.RunLevel = 1 # TASK_RUNLEVEL_HIGHEST

    # CREATE_OR_UPDATE=6, INTERACTIVE_TOKEN=3; no account password is stored.
    [void]$folder.RegisterTaskDefinition($taskName, $definition, 6, $userId, $null, 3, $null)
    Write-Output "Registered '$taskName' for $userId."
    exit 0
}
catch {
    [Console]::Error.WriteLine("Auto strategy task setup failed: " + $_.Exception.Message)
    exit 1
}
