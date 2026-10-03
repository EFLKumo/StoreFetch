Set-StrictMode -Version Latest

function Show-StoreFetchHeader {
    param([string]$Ring = 'Retail')

    Write-Host ''
    Write-Host 'StoreFetch - Microsoft Store package fetcher' -ForegroundColor Cyan
    Write-Host ("Uses agent-browser to query the {0} ring." -f $Ring) -ForegroundColor DarkGray
    Write-Host ''
}

function Show-PackageTable {
    param(
        [Parameter(Mandatory)]
        [object[]]$Packages
    )

    Write-Host ''
    Write-Host ("Found {0} files:" -f $Packages.Count) -ForegroundColor Green
    Write-Host ('    {0,-72} {1,-8} {2,-8} {3,-12}' -f 'Name', 'Arch', 'Type', 'Size') -ForegroundColor DarkGray
    Write-Host ('    {0,-72} {1,-8} {2,-8} {3,-12}' -f ('-' * 72), ('-' * 8), ('-' * 8), ('-' * 12)) -ForegroundColor DarkGray

    foreach ($package in $Packages) {
        $name = [string]$package.Name
        if ($name.Length -gt 72) {
            $name = $name.Substring(0, 69) + '...'
        }

        Write-Host ('[{0,3}] {1,-72} {2,-8} {3,-8} {4,-12}' -f `
                $package.Index,
                $name,
                $package.Architecture,
                $package.Kind,
                $package.Size)
    }
}

$script:TuiEscape = [char]27
$script:TuiAlternateScreen = $false
$script:TuiPendingLines = $null
$script:TuiFrameLines = @()
$script:TuiFrameColors = @()
$script:TuiLastWidth = 0
$script:TuiLastHeight = 0

function Enter-Tui {
    if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) {
        return
    }

    [Console]::Write("$($script:TuiEscape)[?1049h$($script:TuiEscape)[?25l$($script:TuiEscape)[2J$($script:TuiEscape)[H")
    $script:TuiAlternateScreen = $true
    $script:TuiPendingLines = $null
    $script:TuiFrameLines = @()
    $script:TuiFrameColors = @()
    $script:TuiLastWidth = 0
    $script:TuiLastHeight = 0
}

function Exit-Tui {
    if (-not $script:TuiAlternateScreen) {
        return
    }

    [Console]::Write("$($script:TuiEscape)[0m$($script:TuiEscape)[?25h$($script:TuiEscape)[?1049l")
    $script:TuiAlternateScreen = $false
    $script:TuiPendingLines = $null
}

function Get-TuiWidth {
    try {
        $width = [Console]::WindowWidth
    }
    catch {
        $width = 100
    }

    if ($width -lt 70) {
        return 100
    }
    return $width
}

function Write-TuiLine {
    param(
        [AllowEmptyString()]
        [string]$Text = '',
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    if ($null -ne $script:TuiPendingLines) {
        $script:TuiPendingLines.Add([PSCustomObject]@{
            Text  = $Text
            Color = $Color
        })
        return
    }

    $oldColor = [Console]::ForegroundColor
    if (-not [Console]::IsOutputRedirected) {
        [Console]::ForegroundColor = $Color
    }
    [Console]::WriteLine($Text)
    if (-not [Console]::IsOutputRedirected) {
        [Console]::ForegroundColor = $oldColor
    }
}

function Begin-TuiFrame {
    $script:TuiPendingLines = [System.Collections.Generic.List[object]]::new()
}

function Complete-TuiFrame {
    if ($null -eq $script:TuiPendingLines) {
        return
    }

    if (-not $script:TuiAlternateScreen) {
        $pendingLines = @($script:TuiPendingLines)
        $script:TuiPendingLines = $null
        foreach ($line in $pendingLines) {
            Write-TuiLine -Text $line.Text -Color $line.Color
        }
        return
    }

    $width = Get-TuiWidth
    try {
        $height = [Console]::WindowHeight
    }
    catch {
        $height = 24
    }

    $resized = $width -ne $script:TuiLastWidth -or $height -ne $script:TuiLastHeight
    $newLines = @($script:TuiPendingLines | ForEach-Object { [string]$_.Text })
    $newColors = @($script:TuiPendingLines | ForEach-Object { $_.Color })
    $oldCount = $script:TuiFrameLines.Count
    $newCount = $newLines.Count
    $rowCount = [Math]::Max($oldCount, $newCount)

    if ($resized) {
        [Console]::Write("$($script:TuiEscape)[2J$($script:TuiEscape)[H")
    }

    for ($row = 0; $row -lt $rowCount; $row++) {
        $line = if ($row -lt $newCount) { $newLines[$row] } else { '' }
        $lineColor = if ($row -lt $newCount) { $newColors[$row] } else { [ConsoleColor]::Gray }
        $oldLine = if ($row -lt $oldCount) { $script:TuiFrameLines[$row] } else { $null }
        $oldColor = if ($row -lt $script:TuiFrameColors.Count) { $script:TuiFrameColors[$row] } else { $null }

        if ($resized -or $row -ge $oldCount -or $line -ne $oldLine -or $lineColor -ne $oldColor) {
            if ($line.Length -ge $width) {
                $line = $line.Substring(0, $width - 1)
            }
            [Console]::Write("$($script:TuiEscape)[$($row + 1);1H$($script:TuiEscape)[2K")
            $savedColor = [Console]::ForegroundColor
            [Console]::ForegroundColor = $lineColor
            [Console]::Write($line)
            [Console]::ForegroundColor = $savedColor
        }
    }

    $cursorRow = [Math]::Min($newCount, [Math]::Max(0, $height - 1))
    [Console]::Write("$($script:TuiEscape)[$($cursorRow + 1);1H")
    $script:TuiFrameLines = $newLines
    $script:TuiFrameColors = $newColors
    $script:TuiLastWidth = $width
    $script:TuiLastHeight = $height
    $script:TuiPendingLines = $null
}

function Read-TuiKey {
    if ([Console]::IsInputRedirected) {
        throw 'The interactive TUI requires a real console. Run pwsh directly in a terminal.'
    }
    return [Console]::ReadKey($true)
}

function Read-TuiText {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [string]$InitialValue = ''
    )

    if ([Console]::IsInputRedirected) {
        return Read-Host $Prompt
    }

    $value = [System.Text.StringBuilder]::new($InitialValue)
    $cursor = $value.Length
    $promptText = "$Prompt "
    Complete-TuiFrame
    $line = [Console]::CursorTop

    while ($true) {
        $availableWidth = [Math]::Max(20, (Get-TuiWidth) - $promptText.Length - 2)
        $start = [Math]::Max(0, $cursor - $availableWidth)
        $visible = $value.ToString().Substring($start)
        if ($visible.Length -gt $availableWidth) {
            $visible = $visible.Substring(0, $availableWidth)
        }

        [Console]::SetCursorPosition(0, $line)
        [Console]::Write(($promptText + $visible).PadRight([Math]::Min((Get-TuiWidth) - 1, $promptText.Length + $availableWidth)))
        $cursorColumn = [Math]::Min((Get-TuiWidth) - 1, $promptText.Length + ($cursor - $start))
        [Console]::SetCursorPosition($cursorColumn, $line)

        $key = Read-TuiKey
        switch ($key.Key) {
            'Enter' { return $value.ToString() }
            'Escape' { return $null }
            'Backspace' {
                if ($cursor -gt 0) {
                    $value.Remove($cursor - 1, 1) | Out-Null
                    $cursor--
                }
            }
            'Delete' {
                if ($cursor -lt $value.Length) {
                    $value.Remove($cursor, 1) | Out-Null
                }
            }
            'LeftArrow' { $cursor = [Math]::Max(0, $cursor - 1) }
            'RightArrow' { $cursor = [Math]::Min($value.Length, $cursor + 1) }
            'Home' { $cursor = 0 }
            'End' { $cursor = $value.Length }
            default {
                if ([int][char]$key.KeyChar -ge 32) {
                    $value.Insert($cursor, $key.KeyChar) | Out-Null
                    $cursor++
                }
            }
        }
    }
}

function Show-TuiHeader {
    param(
        [string]$Subtitle,
        [string]$Ring = 'Retail'
    )

    Begin-TuiFrame
    Write-TuiLine ' StoreFetch' ([ConsoleColor]::Cyan)
    Write-TuiLine (" Microsoft Store package fetcher - {0} ring" -f $Ring) ([ConsoleColor]::DarkGray)
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-TuiLine " $Subtitle" ([ConsoleColor]::Yellow)
    }
    Write-TuiLine ''
}

function Read-StoreUrlTui {
    param(
        [string]$InitialValue,
        [string]$Ring = 'Retail'
    )

    while ($true) {
        Show-TuiHeader -Ring $Ring -Subtitle 'Paste a Microsoft Store URL'
        Write-TuiLine ' Type the URL, then press Enter. Escape quits.' ([ConsoleColor]::DarkGray)
        Write-TuiLine ''
        Complete-TuiFrame
        $value = Read-TuiText -Prompt 'URL:' -InitialValue $InitialValue
        if ($null -eq $value) {
            return $null
        }

        $value = $value.Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            $InitialValue = ''
            continue
        }

        try {
            $uri = [Uri]$value
            if ($uri.Scheme -notin @('http', 'https')) {
                throw 'The URL must use http:// or https://.'
            }
            return $value
        }
        catch {
            Show-TuiHeader -Ring $Ring -Subtitle 'Invalid URL'
            Write-TuiLine $_.Exception.Message ([ConsoleColor]::Red)
            Write-TuiLine ''
            Write-TuiLine 'Press any key to try again.' ([ConsoleColor]::DarkGray)
            Complete-TuiFrame
            Read-TuiKey | Out-Null
            $InitialValue = $value
        }
    }
}

function Invoke-PackagePickerTui {
    param(
        [Parameter(Mandatory)]
        [object[]]$Packages,
        [Parameter(Mandatory)]
        [string]$DownloadDirectory,
        [Parameter(Mandatory)]
        [hashtable]$DownloadedPaths,
        [string]$Ring = 'Retail'
    )

    $cursor = 0
    $status = 'Enter downloads the highlighted item. Enter again installs it when Add-AppxPackage is available.'
    $addAppxPackage = Get-Command Add-AppxPackage -ErrorAction SilentlyContinue

    while ($true) {
        $width = Get-TuiWidth
        $visibleRows = 12
        try {
            $visibleRows = [Math]::Max(5, [Console]::WindowHeight - 10)
        }
        catch {
            # Keep the default row count.
        }

        $first = [Math]::Max(0, [Math]::Min($cursor - $visibleRows + 1, $Packages.Count - $visibleRows))
        $last = [Math]::Min($Packages.Count - 1, $first + $visibleRows - 1)

        Show-TuiHeader -Ring $Ring -Subtitle 'Choose a package'
        Write-TuiLine ' Up/Down: move   Enter: download/install' ([ConsoleColor]::DarkGray)
        Write-TuiLine ' R: refresh   Q/Esc: quit' ([ConsoleColor]::DarkGray)
        Write-TuiLine ''

        for ($index = $first; $index -le $last; $index++) {
            $package = $Packages[$index]
            $pointer = if ($index -eq $cursor) { '>' } else { ' ' }
            $nameWidth = [Math]::Max(20, $width - 42)
            $name = [string]$package.Name
            if ($name.Length -gt $nameWidth) {
                $name = $name.Substring(0, $nameWidth - 3) + '...'
            }
            $packageKey = [string]$package.Name
            $state = if ($DownloadedPaths.ContainsKey($packageKey)) { 'downloaded' } else { '-' }
            $line = " $pointer {0,-$nameWidth} {1,-6} {2,-8} {3,10} {4,-10}" -f `
                $name, $package.Architecture, $package.Kind, $package.Size, $state
            $color = if ($index -eq $cursor) { [ConsoleColor]::White } elseif ($state -eq 'downloaded') { [ConsoleColor]::Green } else { [ConsoleColor]::Gray }
            Write-TuiLine $line $color
        }

        Write-TuiLine ''
        Write-TuiLine (" Showing {0}-{1} of {2}. Enter acts on the highlighted item." -f ($first + 1), ($last + 1), $Packages.Count) ([ConsoleColor]::DarkGray)
        Write-TuiLine " $status" ([ConsoleColor]::DarkGray)
        Complete-TuiFrame

        $key = Read-TuiKey
        switch ($key.Key) {
            'UpArrow' { $cursor = [Math]::Max(0, $cursor - 1) }
            'DownArrow' { $cursor = [Math]::Min($Packages.Count - 1, $cursor + 1) }
            'Home' { $cursor = 0 }
            'End' { $cursor = $Packages.Count - 1 }
            'R' { return [PSCustomObject]@{ Action = 'refresh'; Packages = @() } }
            'Q' { return [PSCustomObject]@{ Action = 'quit'; Packages = @() } }
            'Escape' { return [PSCustomObject]@{ Action = 'quit'; Packages = @() } }
            'Enter' {
                $package = $Packages[$cursor]
                $packageKey = [string]$package.Name
                if ($DownloadedPaths.ContainsKey($packageKey)) {
                    if ($null -eq $addAppxPackage) {
                        $status = 'Already downloaded. Add-AppxPackage is unavailable, so Enter does nothing.'
                        continue
                    }

                    Show-TuiHeader -Ring $Ring -Subtitle 'Installing package'
                    Write-TuiLine " $($package.Name)" ([ConsoleColor]::White)
                    Write-TuiLine ''
                    Write-TuiLine ' Installing with Add-AppxPackage ...' ([ConsoleColor]::Yellow)
                    Complete-TuiFrame
                    try {
                        Add-AppxPackage -Path $DownloadedPaths[$packageKey] -ErrorAction Stop
                        $status = "Installed $($package.Name)."
                    }
                    catch {
                        $status = "Install failed: $($_.Exception.Message)"
                    }
                    continue
                }

                Show-TuiHeader -Ring $Ring -Subtitle 'Downloading package'
                Write-TuiLine " $($package.Name)" ([ConsoleColor]::White)
                Write-TuiLine " $($package.Size) | $($package.Architecture) | $($package.Kind)" ([ConsoleColor]::DarkGray)
                Write-TuiLine ''
                Write-TuiLine " Saving to $DownloadDirectory" ([ConsoleColor]::DarkGray)
                Write-TuiLine ' Downloading ...' ([ConsoleColor]::Yellow)
                Complete-TuiFrame
                try {
                    $path = Save-StorePackage -Package $package -Directory $DownloadDirectory
                    $DownloadedPaths[$packageKey] = $path
                    $status = "Downloaded $($package.Name). Press Enter again to install if supported."
                }
                catch {
                    $status = "Download failed: $($_.Exception.Message)"
                }
            }
        }
    }
}

function Wait-TuiKey {
    if ([Console]::IsInputRedirected) {
        Read-Host 'Press Enter to continue' | Out-Null
    }
    else {
        Read-TuiKey | Out-Null
    }
}
