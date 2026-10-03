[CmdletBinding()]
param(
    [string]$StoreUrl,
    [string]$DownloadDirectory,
    [ValidateSet('Retail', 'RP', 'WIF', 'WIS')]
    [string]$Ring = 'Retail',
    [switch]$Headed,
    [switch]$ListOnly,
    [switch]$ShowBlockMaps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'StoreFetch.Browser.ps1')
. (Join-Path $PSScriptRoot 'StoreFetch.Downloads.ps1')
. (Join-Path $PSScriptRoot 'StoreFetch.Tui.ps1')

function Start-StoreFetchTui {
    param(
        [string]$InitialStoreUrl,
        [string]$InitialDownloadDirectory,
        [Parameter(Mandatory)]
        [string]$PackageRing,
        [switch]$UseHeadedBrowser,
        [switch]$OnlyList,
        [switch]$IncludeBlockMaps
    )

    $downloadDirectory = if ([string]::IsNullOrWhiteSpace($InitialDownloadDirectory)) {
        (Get-Location).Path
    }
    else {
        [IO.Path]::GetFullPath($InitialDownloadDirectory)
    }
    New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
    $downloadedPaths = @{}

    if ($OnlyList) {
        Show-StoreFetchHeader -Ring $PackageRing
    }
    else {
        Enter-Tui
    }

    try {
        $nextUrl = $InitialStoreUrl
        do {
            if ([string]::IsNullOrWhiteSpace($nextUrl)) {
                $currentUrl = Read-StoreUrlTui -Ring $PackageRing
            }
            else {
                $currentUrl = $nextUrl.Trim()
            }

            if ($null -eq $currentUrl) {
                return
            }

            if (-not $OnlyList) {
                Show-TuiHeader -Ring $PackageRing -Subtitle ("Fetching {0} packages" -f $PackageRing)
                Write-TuiLine " $currentUrl" ([ConsoleColor]::DarkGray)
                Write-TuiLine ''
                Write-TuiLine ' Contacting the Microsoft Store link service ...' ([ConsoleColor]::Yellow)
                Complete-TuiFrame
            }

            try {
                $packages = @(Get-StorePackages -StoreUrl $currentUrl -Ring $PackageRing -Headed:$UseHeadedBrowser)
            }
            catch {
                if ($OnlyList) {
                    throw
                }
                Show-TuiHeader -Ring $PackageRing -Subtitle 'Lookup failed'
                Write-TuiLine $_.Exception.Message ([ConsoleColor]::Red)
                Write-TuiLine ''
                Write-TuiLine 'Press any key to enter another URL.' ([ConsoleColor]::DarkGray)
                Complete-TuiFrame
                Wait-TuiKey
                $nextUrl = $null
                continue
            }

            if (-not $IncludeBlockMaps) {
                $packages = @($packages | Where-Object { $_.Kind -ne 'blockmap' })
            }
            for ($packageIndex = 0; $packageIndex -lt $packages.Count; $packageIndex++) {
                $packages[$packageIndex].Index = $packageIndex + 1
            }

            if ($packages.Count -eq 0) {
                if ($OnlyList) {
                    Write-Host 'No package files found.' -ForegroundColor Red
                    return
                }
                Show-TuiHeader -Ring $PackageRing -Subtitle 'No package files found'
                Write-TuiLine ' The lookup returned no package files for the current filter.' ([ConsoleColor]::Red)
                Write-TuiLine ''
                Write-TuiLine 'Press any key to enter another URL.' ([ConsoleColor]::DarkGray)
                Complete-TuiFrame
                Wait-TuiKey
                $nextUrl = $null
                continue
            }

            if ($OnlyList) {
                Show-PackageTable -Packages $packages
                return
            }

            foreach ($package in $packages) {
                $existingPath = Join-Path $downloadDirectory (Get-SafeFileName -Name ([string]$package.Name))
                if (Test-Path -LiteralPath $existingPath -PathType Leaf) {
                    $downloadedPaths[[string]$package.Name] = $existingPath
                }
            }

            $pickerResult = Invoke-PackagePickerTui `
                -Packages $packages `
                -DownloadDirectory $downloadDirectory `
                -DownloadedPaths $downloadedPaths `
                -Ring $PackageRing
            if ($pickerResult.Action -eq 'quit') {
                return
            }
            if ($pickerResult.Action -eq 'refresh') {
                $nextUrl = $currentUrl
                continue
            }

            $nextUrl = $null
        } while ($true)
    }
    finally {
        Exit-Tui
        Close-AgentBrowser
    }
}

Start-StoreFetchTui `
    -InitialStoreUrl $StoreUrl `
    -InitialDownloadDirectory $DownloadDirectory `
    -PackageRing $Ring `
    -UseHeadedBrowser:$Headed `
    -OnlyList:$ListOnly `
    -IncludeBlockMaps:$ShowBlockMaps
