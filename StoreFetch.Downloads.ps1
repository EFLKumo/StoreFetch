Set-StrictMode -Version Latest

function Get-SafeFileName {
    param([Parameter(Mandatory)][string]$Name)

    $safeName = [IO.Path]::GetFileName($Name) -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    if ([string]::IsNullOrWhiteSpace($safeName) -or $safeName -in @('.', '..')) {
        throw "Unable to create a local filename from '$Name'."
    }
    return $safeName
}

function Get-DownloadPath {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$FileName,
        [switch]$Overwrite
    )

    $candidate = Join-Path $Directory $FileName
    if ($Overwrite -or -not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $base = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [IO.Path]::GetExtension($FileName)
    $counter = 1
    do {
        $candidate = Join-Path $Directory ("{0} ({1}){2}" -f $base, $counter, $extension)
        $counter++
    } while (Test-Path -LiteralPath $candidate)

    return $candidate
}

function Save-StorePackage {
    param(
        [Parameter(Mandatory)]
        [object]$Package,
        [Parameter(Mandatory)]
        [string]$Directory,
        [switch]$Overwrite
    )

    $fileName = Get-SafeFileName -Name ([string]$Package.Name)
    $destination = Get-DownloadPath -Directory $Directory -FileName $fileName -Overwrite:$Overwrite
    $partial = "$destination.$([Guid]::NewGuid().ToString('N')).part"
    $oldProgressPreference = $ProgressPreference

    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest `
            -Uri ([string]$Package.Url) `
            -OutFile $partial `
            -MaximumRedirection 10 `
            -TimeoutSec 300 `
            -UseBasicParsing `
            -ErrorAction Stop
        Move-Item -LiteralPath $partial -Destination $destination -Force
        return $destination
    }
    catch {
        if (Test-Path -LiteralPath $partial) {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        $ProgressPreference = $oldProgressPreference
    }
}
