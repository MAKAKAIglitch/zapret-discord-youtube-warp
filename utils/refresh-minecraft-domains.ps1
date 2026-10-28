$ErrorActionPreference = 'SilentlyContinue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'lists\minecraft-domains.txt'
$outputPath = Join-Path $repoRoot 'lists\minecraft-domains-resolved.txt'
$addresses = @()

if (Test-Path -LiteralPath $sourcePath) {
    foreach ($entry in Get-Content -LiteralPath $sourcePath) {
        $domainName = $entry.Trim()

        if (-not $domainName -or $domainName.StartsWith('#')) {
            continue
        }

        # Accept DNS names only; comments and malformed entries are ignored.
        if ($domainName -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.?$' -or
            $domainName.StartsWith('.') -or
            $domainName.Contains('..')) {
            continue
        }

        try {
            $addresses += [System.Net.Dns]::GetHostAddresses($domainName) |
                ForEach-Object { $_.IPAddressToString }
        } catch {
            # A domain that cannot currently resolve is skipped; static IP entries still work.
        }
    }
}

$uniqueAddresses = @($addresses | Sort-Object -Unique)
[System.IO.File]::WriteAllLines(
    $outputPath,
    [string[]]$uniqueAddresses,
    [System.Text.Encoding]::ASCII
)

Write-Output $uniqueAddresses.Count
