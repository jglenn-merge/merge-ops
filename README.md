# MergeOps

MergeOps is a PowerShell module of operational utilities for teams that build and run web platforms on Windows. It covers web diagnostics, connectivity checks, IIS, Windows Server maintenance, release folders, Sitecore deploy cleanup, .NET project maintenance, and GitHub organization administration.

## Requirements

- Windows PowerShell 5.1. All tests were run on 5.1. PowerShell 7 should work for everything except the IIS functions, but it has not been tested.
- The WebAdministration module and an elevated session for the IIS functions.
- The GitHub CLI (`gh`), signed in with `gh auth login`, for the GitHub functions.
- Pester 5 to run the tests. Windows ships with Pester 3.4, which cannot run them.

## Installation

Import the module from wherever the `MergeOps` folder is saved.

```powershell
Import-Module path\to\MergeOps\MergeOps.psd1
Get-Command -Module MergeOps
```

To make it available in every session, copy the `MergeOps` folder into a folder on `$env:PSModulePath`, such as `$HOME\Documents\WindowsPowerShell\Modules`. After that, `Import-Module MergeOps` works by name.

## Layout

```
MergeOps/
  MergeOps.psd1          Manifest. FunctionsToExport is the public interface.
  MergeOps.psm1          Dot-sources Private and Public, exports Public.
  Public/<Category>/     One file per exported function.
  Private/<Area>/        Shared helpers. Never exported.
  Tests/                 Pester 5 tests.
```

Each public function lives in a file with the same name, inside a category folder. The root module exports every file under `Public`, and a test checks that the manifest's `FunctionsToExport` list matches. Adding a function means adding the file and adding its name to the manifest.

The private helpers carry the logic that several public functions share. These include the timed HTTP request wrapper, the TCP client, the project file loader, the gh CLI wrapper, and the folder age sort.

## Naming

Categories map to function names in two ways. Platform categories put the platform in the noun (`Web`, `IIS`, `Sitecore`, `DotNet`, `GitHub`), so `Get-Command *-Web*` or `Get-Command *-IIS*` lists a whole category. Connectivity functions all follow `Test-<Protocol>Connection`. Server and Release functions use plain descriptive nouns, because a prefix such as `Server` reads awkwardly on file maintenance commands.

## Functions

Every function has comment-based help with examples. Run `Get-Help <name> -Examples` to see them.

### Web

| Function | Purpose |
|---|---|
| `Invoke-WebWarmup` | Requests a base URL and a page list after a deploy, with optional basic auth and login cookie bypass. |
| `Measure-WebLatency` | Compares response times across URLs with interleaved requests. |
| `Test-WebLoadBalancing` | Groups responses by a backend instance header to show load balancer distribution. |
| `Watch-WebEndpoint` | Requests a URL in a loop until it fails, and logs the failure detail. |
| `Find-WebExternalDomain` | Lists external script and stylesheet hosts in a codebase as input for a Content Security Policy. |

### Connectivity

| Function | Purpose |
|---|---|
| `Test-SmtpConnection` | Checks TCP connectivity to an SMTP server, with an optional authenticated test send. |
| `Test-SqlConnection` | Opens a SQL Server connection from a connection string or a server and database. |
| `Test-RedisConnection` | Connects to Redis, optionally authenticates over TLS, and sends PING. No Redis client needs to be installed. |

### IIS

| Function | Purpose |
|---|---|
| `Get-IISBindingReport` | Lists site bindings with certificate subject and expiry. |
| `Export-IISCertificate` | Exports each bound certificate once to a password-protected PFX. |
| `ConvertFrom-IISLog` | Parses W3C logs using the `#Fields:` header, with a UTC timestamp. |

### Server

| Function | Purpose |
|---|---|
| `Repair-StoppedService` | Starts any named services that are not running. |
| `Remove-StaleFile` | Deletes files past a retention period, with include and exclude patterns. |
| `Find-LongFilePath` | Finds paths at or above a length threshold, including paths already past 260 characters. |

### Release

| Function | Purpose |
|---|---|
| `New-ReleaseFolder` | Creates a versioned release folder, optionally seeded from the previous release. |
| `Compress-ReleaseFolder` | Zips all but the newest N release folders, with optional removal. |

### Sitecore

| Function | Purpose |
|---|---|
| `Clear-SitecoreBinFolder` | Strips a site's bin folder down to an allow list before deploy. |

### DotNet

| Function | Purpose |
|---|---|
| `Find-DotNetMissingFile` | Lists project items whose files do not exist. Accepts a project or a solution. |
| `Remove-DotNetPackagesConfig` | Removes packages.config wiring from projects, optionally adding PackageReference items. |

### GitHub

| Function | Purpose |
|---|---|
| `Find-GitHubWorkflowUsage` | Searches GitHub Actions workflow files across an organization. |
| `Set-GitHubRepoVisibility` | Changes repo visibility in bulk, with confirmation, exclusions, and `-WhatIf`. |

## Usage Notes

Some behavior is worth knowing before using these functions in a pipeline or deployment step.

- No function stores credentials. Secrets are passed as `[pscredential]` or `[securestring]` parameters.
- Every function that deletes, moves, or changes something supports `-WhatIf` and `-Confirm`. `Set-GitHubRepoVisibility` and `Remove-DotNetPackagesConfig` prompt for each change by default, so pass `-Confirm:$false` for unattended runs.
- `Invoke-WebWarmup` requests every page even when one fails, then throws once at the end. A deployment step running it still fails, but the output shows every failing page.
- `New-ReleaseFolder` picks the previous release by creation time. On a redeploy of the same release, it returns the existing folder with a warning instead of failing. It also resets `$LASTEXITCODE` to 0 after a successful robocopy, because Octopus fails a PowerShell step that ends with a non-zero exit code.
- `Export-IISCertificate` reads each binding's own certificate store, so SNI certificates in the WebHosting store are included. Certificates without an exportable private key are reported as `Failed`.
- `Find-DotNetMissingFile` skips assembly and package references, and skips includes that use wildcards or MSBuild properties, because those cannot be checked without evaluating the project.
- `Remove-DotNetPackagesConfig` edits the project XML directly, so it runs outside Visual Studio. With `-AddPackageReference`, every package in packages.config is added, including transitive dependencies, so prune the list afterwards.
- `Find-GitHubWorkflowUsage` skips archived repos unless `-IncludeArchived` is set.
- `Test-RedisConnection` needs `-UseTls` for Azure Cache for Redis, which disables the non-TLS port by default.

## Running the Tests

Install Pester 5 for the current user, then run the suite from the module folder.

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -SkipPublisherCheck
Invoke-Pester -Path path\to\MergeOps\Tests -Output Detailed
```

The tests mock HTTP and gh calls and use temporary folders. They make no network requests beyond localhost and change nothing outside the Pester test drive. The IIS functions that need an elevated session are covered only through their binding parser.
