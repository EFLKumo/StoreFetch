Set-StrictMode -Version Latest

$script:StoreFetchAgentBrowserPath = $null
$script:StoreFetchAgentBrowserSession = $null
$script:StoreFetchAgentBrowserHeaded = $false

function Initialize-AgentBrowser {
    [CmdletBinding()]
    param(
        [switch]$Headed
    )

    $command = Get-Command agent-browser -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "agent-browser was not found. Install it with: npm install -g agent-browser"
    }

    $script:StoreFetchAgentBrowserPath = $command.Source
    if ([string]::IsNullOrWhiteSpace($script:StoreFetchAgentBrowserPath)) {
        $script:StoreFetchAgentBrowserPath = $command.Path
    }

    # A unique session prevents this script from taking over another agent-browser session.
    $script:StoreFetchAgentBrowserSession = "storefetch-$([Guid]::NewGuid().ToString('N'))"
    $script:StoreFetchAgentBrowserHeaded = $Headed.IsPresent
}

function Invoke-AgentBrowser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    if ([string]::IsNullOrWhiteSpace($script:StoreFetchAgentBrowserPath)) {
        throw 'agent-browser has not been initialized.'
    }

    $invokeArguments = @('--session', $script:StoreFetchAgentBrowserSession)
    if ($script:StoreFetchAgentBrowserHeaded) {
        $invokeArguments += '--headed'
    }
    $invokeArguments += $Arguments

    $output = & $script:StoreFetchAgentBrowserPath @invokeArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "agent-browser failed ($LASTEXITCODE): $message"
    }

    return ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
}

function Invoke-AgentBrowserJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Script
    )

    $encodedScript = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes($Script)
    )
    $raw = Invoke-AgentBrowser -Arguments @('eval', '--json', '-b', $encodedScript)

    try {
        $envelope = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "agent-browser returned invalid JSON: $($_.Exception.Message)"
    }

    if (-not $envelope.success) {
        $errorText = [string]$envelope.data.error
        if ([string]::IsNullOrWhiteSpace($errorText)) {
            $errorText = 'unknown browser error'
        }
        throw "agent-browser evaluation failed: $errorText"
    }

    return $envelope.data.result
}

function ConvertTo-StorePackageObjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $packages = [System.Collections.Generic.List[object]]::new()
    $seen = @{}

    foreach ($row in $Rows) {
        $name = [string]$row.name
        $url = [string]$row.url
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($url)) {
            continue
        }

        $key = "$name|$url"
        if ($seen.ContainsKey($key)) {
            continue
        }
        $seen[$key] = $true

        $architecture = '-'
        if ($name -match '_(arm64|arm|x64|x86)(?:__|\.|$)') {
            $architecture = $Matches[1]
        }

        $extension = [IO.Path]::GetExtension($name)
        $kind = if ([string]::IsNullOrWhiteSpace($extension)) {
            'file'
        }
        else {
            $extension.TrimStart('.').ToLowerInvariant()
        }

        $packages.Add([PSCustomObject]@{
            Index        = $packages.Count + 1
            Name         = $name
            Url          = $url
            Expire       = [string]$row.expire
            Hash         = [string]$row.hash
            Size         = [string]$row.size
            Architecture = $architecture
            Kind         = $kind
        })
    }

    return @($packages)
}

function Get-StorePackagesFromBrowserApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StoreUrl,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Ring
    )

    Invoke-AgentBrowser -Arguments @('open', 'https://store.rg-adguard.net/') | Out-Null
    Invoke-AgentBrowser -Arguments @('wait', '--load', 'domcontentloaded') | Out-Null

    $storeUrlLiteral = $StoreUrl | ConvertTo-Json -Compress
    $ringLiteral = $Ring | ConvertTo-Json -Compress
    $script = @"
(async () => {
  const body = new URLSearchParams({
    type: 'url',
    url: $storeUrlLiteral,
    ring: $ringLiteral,
    lang: 'en-US'
  });
  const response = await fetch('./api/GetFiles', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'X-Requested-With': 'XMLHttpRequest'
    },
    body
  });
  const html = await response.text();
  const document = new DOMParser().parseFromString(html, 'text/html');
  const rows = Array.from(document.querySelectorAll('table.tftable tbody tr'));
  return rows.map(row => {
    const cells = Array.from(row.querySelectorAll('td')).map(cell => cell.innerText.trim());
    const link = row.querySelector('a[href*="filestreamingservice/files"]');
    if (!link) return null;
    return {
      name: link.innerText.trim(),
      url: new URL(link.getAttribute('href'), location.href).href,
      expire: cells[1] || '',
      hash: cells[2] || '',
      size: cells[3] || ''
    };
  }).filter(Boolean);
})()
"@

    $result = @(Invoke-AgentBrowserJson -Script $script)
    $packages = ConvertTo-StorePackageObjects -Rows $result
    if ($packages.Count -eq 0) {
        throw 'The browser API response did not contain any package links.'
    }
    return $packages
}

function Get-StorePackagesFromBrowserUi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StoreUrl,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Ring
    )

    Invoke-AgentBrowser -Arguments @('open', 'https://store.rg-adguard.net/') | Out-Null
    Invoke-AgentBrowser -Arguments @('wait', '--load', 'domcontentloaded') | Out-Null
    Invoke-AgentBrowser -Arguments @('wait', '#url') | Out-Null
    Invoke-AgentBrowser -Arguments @('fill', '#url', $StoreUrl) | Out-Null
    Invoke-AgentBrowser -Arguments @('select', '#ring', $Ring) | Out-Null
    Invoke-AgentBrowser -Arguments @('click', 'input[type=button]') | Out-Null
    Invoke-AgentBrowser -Arguments @('wait', '--fn', 'document.querySelectorAll("table.tftable tbody tr").length > 0') | Out-Null

    $script = @'
Array.from(document.querySelectorAll('table.tftable tbody tr')).map(row => {
  const cells = Array.from(row.querySelectorAll('td')).map(cell => cell.innerText.trim());
  const link = row.querySelector('a[href*="filestreamingservice/files"]');
  if (!link) return null;
  return {
    name: link.innerText.trim(),
    url: link.href,
    expire: cells[1] || '',
    hash: cells[2] || '',
    size: cells[3] || ''
  };
}).filter(Boolean)
'@

    $result = @(Invoke-AgentBrowserJson -Script $script)
    $packages = ConvertTo-StorePackageObjects -Rows $result
    if ($packages.Count -eq 0) {
        throw 'The browser UI did not contain any package links.'
    }
    return $packages
}

function Get-StorePackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StoreUrl,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Ring,
        [switch]$Headed
    )

    if ([string]::IsNullOrWhiteSpace($script:StoreFetchAgentBrowserSession)) {
        Initialize-AgentBrowser -Headed:$Headed
    }
    try {
        return @(Get-StorePackagesFromBrowserUi -StoreUrl $StoreUrl -Ring $Ring)
    }
    catch {
        $browserUiError = $_.Exception.Message
    }

    try {
        return @(Get-StorePackagesFromBrowserApi -StoreUrl $StoreUrl -Ring $Ring)
    }
    catch {
        $browserApiError = $_.Exception.Message
    }

    throw @"
Unable to retrieve package links.
Browser UI: $browserUiError
Browser API fallback: $browserApiError
"@
}

function Close-AgentBrowser {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($script:StoreFetchAgentBrowserSession)) {
        try {
            Invoke-AgentBrowser -Arguments @('close') | Out-Null
        }
        catch {
            # Cleanup should not hide a successful download or lookup.
        }
    }
}
