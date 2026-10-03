# StoreFetch

`StoreFetch.ps1` is a small PowerShell TUI for retrieving Microsoft Store package links from a Microsoft Store ring.

It opens `store.rg-adguard.net` in an isolated `agent-browser` session, fills the URL, selects the requested ring, clicks the lookup button, and scrapes the rendered results table. An in-browser API request is retained only as a fallback if the site UI changes or fails.

## Requirements

- PowerShell 7 (`pwsh`)
- Node.js and `agent-browser`

Install the browser tool once:

```powershell
npm install -g agent-browser
agent-browser install
```

## Run

From this directory:

```powershell
pwsh ./StoreFetch.ps1
```

Or provide the example URL immediately:

```powershell
pwsh ./StoreFetch.ps1 -StoreUrl 'https://apps.microsoft.com/detail/9pktq5699m62'
```

Use `-Ring RP` (or `Retail`, `WIF`, or `WIS`) to choose a ring; `Retail` is the default. Use `-Headed` to show the browser window while the lookup runs. Use `-ListOnly` to print the package table without entering the TUI. Block maps are hidden by default; add `-ShowBlockMaps` to include them.

Navigate with the arrow keys. Press Enter on a package to download it immediately. Press Enter again on a downloaded package to install it with `Add-AppxPackage` when that cmdlet is available. Downloads go to the caller's current directory by default; use `-DownloadDirectory` to override it. Existing files receive a numbered suffix.

The service returns package files and dependency files such as `.appx`, `.eappx`, `.msix`, and `.BlockMap`. The TUI shows installable package files by default and includes block maps only with `-ShowBlockMaps`.
