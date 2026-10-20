#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $ModuleRoot 'MergeOps.psd1') -Force
}

AfterAll {
    Remove-Module MergeOps -ErrorAction SilentlyContinue
}

Describe 'Module structure' {
    It 'exports exactly the functions in Public' {
        $public = @(Get-ChildItem (Join-Path $ModuleRoot 'Public') -Filter *.ps1 -Recurse | ForEach-Object BaseName | Sort-Object)
        $exported = @((Get-Module MergeOps).ExportedFunctions.Keys | Sort-Object)
        $exported | Should -Be $public
    }

    It 'lists every public function in the manifest' {
        $public = @(Get-ChildItem (Join-Path $ModuleRoot 'Public') -Filter *.ps1 -Recurse | ForEach-Object BaseName | Sort-Object)
        $manifest = Import-PowerShellDataFile (Join-Path $ModuleRoot 'MergeOps.psd1')
        @($manifest.FunctionsToExport | Sort-Object) | Should -Be $public
    }

    It 'does not export private helpers' {
        $private = Get-ChildItem (Join-Path $ModuleRoot 'Private') -Filter *.ps1 -Recurse | ForEach-Object BaseName
        foreach ($name in $private) {
            (Get-Module MergeOps).ExportedFunctions.ContainsKey($name) | Should -BeFalse -Because "$name is private"
        }
    }

    It 'has a synopsis and an example for every public function' {
        foreach ($command in (Get-Command -Module MergeOps)) {
            $help = Get-Help $command.Name -Full
            $help.Synopsis | Should -Not -BeLike "$($command.Name)*" -Because "$($command.Name) needs a synopsis"
            @($help.Examples.Example).Count | Should -BeGreaterThan 0 -Because "$($command.Name) needs an example"
        }
    }
}

Describe 'Private helpers' {
    It 'Test-WildcardMatch matches any pattern' {
        InModuleScope MergeOps {
            Test-WildcardMatch -Value 'Sitecore.Kernel.dll' -Pattern @('Merge*', 'Sitecore.*') | Should -BeTrue
            Test-WildcardMatch -Value 'Other.dll' -Pattern @('Merge*', 'Sitecore.*') | Should -BeFalse
            Test-WildcardMatch -Value 'Other.dll' -Pattern @() | Should -BeFalse
        }
    }

    It 'Get-LatencyStatistic computes median for even and odd counts' {
        InModuleScope MergeOps {
            (Get-LatencyStatistic -Value 10, 20, 30).Median | Should -Be 20
            (Get-LatencyStatistic -Value 10, 20, 30, 40).Median | Should -Be 25
            (Get-LatencyStatistic -Value 10, 20, 30, 40).Average | Should -Be 25
            (Get-LatencyStatistic -Value @()).Average | Should -BeNullOrEmpty
        }
    }

    It 'ConvertFrom-IISBindingInformation parses IPv4, IPv6, and non-HTTP bindings' {
        InModuleScope MergeOps {
            $v4 = ConvertFrom-IISBindingInformation -BindingInformation '*:443:www.example.com'
            $v4.IPAddress | Should -Be '*'
            $v4.Port | Should -Be 443
            $v4.HostName | Should -Be 'www.example.com'

            $v6 = ConvertFrom-IISBindingInformation -BindingInformation '[::1]:80:'
            $v6.IPAddress | Should -Be '[::1]'
            $v6.Port | Should -Be 80
            $v6.HostName | Should -Be ''

            $tcp = ConvertFrom-IISBindingInformation -BindingInformation '808:*'
            $tcp.Port | Should -BeNullOrEmpty
            $tcp.BindingInformation | Should -Be '808:*'
        }
    }

    It 'New-BasicAuthHeader encodes user and password' {
        InModuleScope MergeOps {
            $credential = New-Object pscredential('user', (ConvertTo-SecureString 'p@ss' -AsPlainText -Force))
            (New-BasicAuthHeader -Credential $credential).Authorization | Should -Be 'Basic dXNlcjpwQHNz'
        }
    }
}

Describe 'Web' {
    BeforeEach {
        $global:MergeOpsTestCalls = 0
    }

    AfterAll {
        Remove-Variable -Name MergeOpsTestCalls -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'Invoke-WebWarmup' {
        It 'requests the base URL and each newline-delimited page' {
            Mock -ModuleName MergeOps Invoke-TimedRequest {
                [pscustomobject]@{ Timestamp = Get-Date; Uri = $Uri; Success = $true; StatusCode = 200; ElapsedMs = 5; Headers = @{}; Content = 'ok'; Error = $null }
            }

            $results = @(Invoke-WebWarmup -BaseUrl 'https://example.test/' -Path "about`r`ncontact`n", '/news')

            $results.Count | Should -Be 4
            $results[1].Uri | Should -Be 'https://example.test/about'
            $results[3].Uri | Should -Be 'https://example.test/news'
        }

        It 'retries the base URL with the auth cookie when the login page is detected' {
            Mock -ModuleName MergeOps Invoke-TimedRequest {
                [pscustomobject]@{ Timestamp = Get-Date; Uri = $Uri; Success = $true; StatusCode = 200; ElapsedMs = 5; Headers = @{}; Content = '<form id="sc-auth-form">'; Error = $null }
            }

            Invoke-WebWarmup -BaseUrl 'https://example.test' -AuthPattern 'sc-auth-form' | Out-Null

            # Both calls share one session object, so the recorded session holds the cookie by the time this runs.
            Should -Invoke -ModuleName MergeOps Invoke-TimedRequest -Times 2 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.test' -and
                $WebSession.Cookies.GetCookies([uri]'https://example.test')['sc-auth-successful'].Value -eq 'true'
            }
        }

        It 'does not retry when the auth pattern does not match' {
            Mock -ModuleName MergeOps Invoke-TimedRequest {
                [pscustomobject]@{ Timestamp = Get-Date; Uri = $Uri; Success = $true; StatusCode = 200; ElapsedMs = 5; Headers = @{}; Content = '<html>home</html>'; Error = $null }
            }

            Invoke-WebWarmup -BaseUrl 'https://example.test' -AuthPattern 'sc-auth-form' | Out-Null

            Should -Invoke -ModuleName MergeOps Invoke-TimedRequest -Times 1 -Exactly
        }

        It 'attempts every page and throws once at the end when any fail' {
            Mock -ModuleName MergeOps Invoke-TimedRequest {
                $ok = $Uri -notlike '*broken*'
                [pscustomobject]@{ Timestamp = Get-Date; Uri = $Uri; Success = $ok; StatusCode = $(if ($ok) { 200 } else { 500 }); ElapsedMs = 5; Headers = @{}; Content = ''; Error = $(if ($ok) { $null } else { 'boom' }) }
            }

            { Invoke-WebWarmup -BaseUrl 'https://example.test' -Path 'broken', 'fine' -WarningAction SilentlyContinue } | Should -Throw '*1 of 2*'
            Should -Invoke -ModuleName MergeOps Invoke-TimedRequest -Times 3 -Exactly
        }
    }

    Context 'Measure-WebLatency' {
        It 'interleaves URLs and summarizes successful requests only' {
            Mock -ModuleName MergeOps Invoke-TimedRequest {
                $global:MergeOpsTestCalls++
                $ok = -not ($Uri -like '*b*' -and $global:MergeOpsTestCalls -eq 2)
                [pscustomobject]@{ Timestamp = Get-Date; Uri = $Uri; Success = $ok; StatusCode = 200; ElapsedMs = [double](10 * $global:MergeOpsTestCalls); Headers = @{}; Content = $null; Error = $null }
            }

            $summary = @(Measure-WebLatency -Uri 'https://a.test', 'https://b.test' -Count 3)

            $summary.Count | Should -Be 2
            ($summary | Where-Object Uri -eq 'https://a.test').AverageMs | Should -Be 30
            ($summary | Where-Object Uri -eq 'https://b.test').Failures | Should -Be 1
            ($summary | Where-Object Uri -eq 'https://b.test').AverageMs | Should -Be 50
        }
    }

    Context 'Test-WebLoadBalancing' {
        It 'groups responses by the instance header' {
            Mock -ModuleName MergeOps Invoke-TimedRequest {
                $global:MergeOpsTestCalls++
                $instance = @('node-a', 'node-b', 'node-a', 'node-a')[($global:MergeOpsTestCalls - 1) % 4]
                [pscustomobject]@{ Timestamp = Get-Date; Uri = $Uri; Success = $true; StatusCode = 200; ElapsedMs = 10; Headers = @{ 'X-Current-Instance' = $instance }; Content = $null; Error = $null }
            }

            $summary = @(Test-WebLoadBalancing -Uri 'https://lb.test' -Count 8)

            $summary[0].Instance | Should -Be 'node-a'
            $summary[0].Requests | Should -Be 6
            $summary[0].Percent | Should -Be 75
            $summary[1].Instance | Should -Be 'node-b'
        }
    }

    Context 'Watch-WebEndpoint' {
        It 'stops at the first failure and logs it' {
            Mock -ModuleName MergeOps Invoke-TimedRequest {
                $global:MergeOpsTestCalls++
                $ok = $global:MergeOpsTestCalls -ne 3
                [pscustomobject]@{ Timestamp = Get-Date; Uri = $Uri; Success = $ok; StatusCode = $(if ($ok) { 200 } else { 503 }); ElapsedMs = 1; Headers = @{}; Content = $null; Error = 'Service Unavailable'; ExceptionType = 'System.Net.WebException' }
            }
            $log = Join-Path $TestDrive 'errors.log'

            $failures = @(Watch-WebEndpoint -Uri 'https://localhost/x' -DelayMs 0 -LogPath $log)

            $failures.Count | Should -Be 1
            $failures[0].RequestNumber | Should -Be 3
            $failures[0].StatusCode | Should -Be 503
            Get-Content $log -Raw | Should -Match 'Request Number: 3'
        }

        It 'stops at MaxRequests when nothing fails' {
            Mock -ModuleName MergeOps Invoke-TimedRequest {
                [pscustomobject]@{ Timestamp = Get-Date; Uri = $Uri; Success = $true; StatusCode = 200; ElapsedMs = 1; Headers = @{}; Content = $null; Error = $null }
            }

            @(Watch-WebEndpoint -Uri 'https://localhost/x' -DelayMs 0 -MaxRequests 5).Count | Should -Be 0
            Should -Invoke -ModuleName MergeOps Invoke-TimedRequest -Times 5 -Exactly
        }
    }

    Context 'Find-WebExternalDomain' {
        It 'finds script and link hosts and skips excluded folders' {
            $site = Join-Path $TestDrive 'site'
            New-Item -ItemType Directory -Path (Join-Path $site 'Views'), (Join-Path $site 'node_modules\pkg') -Force | Out-Null
            Set-Content (Join-Path $site 'Views\Layout.cshtml') @'
<script src="https://cdn.example.com/app.js"></script>
<link rel="stylesheet"
      href="//Fonts.Example.org/css?family=x">
<a href="https://not-counted.example.net/">link</a>
<script type="text/javascript" src='https://cdn.example.com/other.js'></script>
'@
            Set-Content (Join-Path $site 'node_modules\pkg\index.html') '<script src="https://ignored.example.com/x.js"></script>'

            $domains = @(Find-WebExternalDomain -Path $site)

            $domains.Domain | Should -Be @('cdn.example.com', 'fonts.example.org')
            ($domains | Where-Object Domain -eq 'cdn.example.com').References | Should -Be 2
            ($domains | Where-Object Domain -eq 'cdn.example.com').Files | Should -Be @('Views\Layout.cshtml')
        }
    }
}

Describe 'Connectivity' {
    BeforeAll {
        $script:Listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
        $Listener.Start()
        $script:OpenPort = $Listener.LocalEndpoint.Port

        $probe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
        $probe.Start()
        $script:ClosedPort = $probe.LocalEndpoint.Port
        $probe.Stop()
    }

    AfterAll {
        $Listener.Stop()
    }

    It 'Test-SmtpConnection reports an open port without sending mail' {
        $result = Test-SmtpConnection -SmtpServer 127.0.0.1 -Port $OpenPort
        $result.TcpConnected | Should -BeTrue
        $result.MessageSent | Should -BeNullOrEmpty
    }

    It 'Test-SmtpConnection reports a closed port' {
        $result = Test-SmtpConnection -SmtpServer 127.0.0.1 -Port $ClosedPort -TimeoutMs 2000
        $result.TcpConnected | Should -BeFalse
        $result.Error | Should -Match 'Could not open'
    }

    It 'Test-SmtpConnection requires -From with -To' {
        { Test-SmtpConnection -SmtpServer 127.0.0.1 -To 'a@example.com' } | Should -Throw '*-From*'
    }

    It 'Test-RedisConnection defaults the port from -UseTls' {
        (Test-RedisConnection -HostName 127.0.0.1 -TimeoutMs 500).Port | Should -Be 6379
        (Test-RedisConnection -HostName 127.0.0.1 -UseTls -TimeoutMs 500).Port | Should -Be 6380
    }

    It 'Test-RedisConnection reports a closed port' {
        $result = Test-RedisConnection -HostName 127.0.0.1 -Port $ClosedPort -TimeoutMs 2000
        $result.Connected | Should -BeFalse
        $result.Success | Should -BeFalse
        $result.Error | Should -Not -BeNullOrEmpty
    }

    It 'Send-RedisCommand writes RESP and reads one reply line' {
        InModuleScope MergeOps {
            # The command is written at position 0, so reserve its 14 bytes and place the reply right after them.
            $expectedCommand = "*1`r`n`$4`r`nPING`r`n"
            $buffer = [Text.Encoding]::ASCII.GetBytes((' ' * $expectedCommand.Length) + "+PONG`r`nEXTRA")
            $stream = New-Object System.IO.MemoryStream
            $stream.Write($buffer, 0, $buffer.Length)
            $stream.Position = 0

            Send-RedisCommand -Stream $stream -Argument @('PING') | Should -Be '+PONG'

            $stream.Position | Should -Be ($expectedCommand.Length + 7)
            [Text.Encoding]::ASCII.GetString($stream.ToArray(), 0, $expectedCommand.Length) | Should -Be $expectedCommand
        }
    }

    It 'Test-SqlConnection never echoes the password' {
        $credential = New-Object pscredential('sa', (ConvertTo-SecureString 'Secret123!' -AsPlainText -Force))
        $result = Test-SqlConnection -ServerInstance "127.0.0.1,$ClosedPort" -Credential $credential -ConnectTimeout 2
        $result.Success | Should -BeFalse
        $result.DataSource | Should -Be "127.0.0.1,$ClosedPort"
        $result.Database | Should -Be 'master'
        ($result | Out-String) | Should -Not -Match 'Secret123'
    }

    It 'Test-SqlConnection accepts a connection string' {
        $result = Test-SqlConnection -ConnectionString "Server=127.0.0.1,$ClosedPort;Database=web;User ID=u;Password=Secret123!" -ConnectTimeout 2
        $result.DataSource | Should -Be "127.0.0.1,$ClosedPort"
        $result.Database | Should -Be 'web'
        $result.Success | Should -BeFalse
        ($result | Out-String) | Should -Not -Match 'Secret123'
    }
}

Describe 'IIS' {
    It 'ConvertFrom-IISLog uses the #Fields header and adds a UTC timestamp' {
        $log = Join-Path $TestDrive 'u_ex1.log'
        Set-Content $log @'
#Software: Microsoft Internet Information Services 10.0
#Fields: date time c-ip cs-uri-stem sc-status X-Forwarded-For
2025-10-15 18:32:46 10.0.0.1 /home 200 203.0.113.9
2025-10-15 18:32:47 10.0.0.2 /about 404 -
'@
        $rows = @(ConvertFrom-IISLog -Path $log)

        $rows.Count | Should -Be 2
        $rows[0].'X-Forwarded-For' | Should -Be '203.0.113.9'
        $rows[1].'sc-status' | Should -Be '404'
        $rows[0].Timestamp.Kind | Should -Be 'Utc'
        $rows[0].Timestamp.Hour | Should -Be 18
        $rows[0].PSObject.Properties.Name[0] | Should -Be 'Timestamp'
    }

    It 'ConvertFrom-IISLog falls back to default fields and names extra columns' {
        $log = Join-Path $TestDrive 'noheader.log'
        Set-Content $log '2025-10-15 18:32:46 10.209.32.168 GET /wp-login.php - 80 - 10.187.186.7 UA - 301 0 0 2 216.173.80.24'

        $row = ConvertFrom-IISLog -Path $log
        $row.'cs-uri-stem' | Should -Be '/wp-login.php'
        $row.'c-ip' | Should -Be '10.187.186.7'
        $row.Field15 | Should -Be '216.173.80.24'
    }

    It 'ConvertFrom-IISLog accepts files from the pipeline' {
        $rows = @(Get-ChildItem $TestDrive -Filter *.log | ConvertFrom-IISLog)
        $rows.Count | Should -BeGreaterOrEqual 3
    }
}

Describe 'Server' {
    It 'Remove-StaleFile removes only old files that match the include patterns' {
        $folder = Join-Path $TestDrive 'backups'
        New-Item -ItemType Directory -Path $folder | Out-Null
        foreach ($name in 'old.bak', 'new.bak', 'old.log', 'keep-old.bak') {
            Set-Content (Join-Path $folder $name) 'x'
        }
        foreach ($name in 'old.bak', 'old.log', 'keep-old.bak') {
            (Get-Item (Join-Path $folder $name)).LastWriteTime = (Get-Date).AddDays(-10)
        }

        $whatIf = @(Remove-StaleFile -Path $folder -OlderThanDays 5 -Include '*.bak' -Exclude 'keep*' -WhatIf)
        $whatIf.Count | Should -Be 0
        (Get-ChildItem $folder).Count | Should -Be 4

        $removed = @(Remove-StaleFile -Path $folder -OlderThanDays 5 -Include '*.bak' -Exclude 'keep*' -Confirm:$false)
        $removed.Name | Should -Be @('old.bak')
        (Get-ChildItem $folder).Name | Sort-Object | Should -Be @('keep-old.bak', 'new.bak', 'old.log')
    }

    It 'Find-LongFilePath reports files at or above the threshold' {
        $deep = Join-Path $TestDrive 'aaaa\bbbb\cccc'
        New-Item -ItemType Directory -Path $deep -Force | Out-Null
        $file = Join-Path $deep 'file.txt'
        Set-Content $file 'x'
        $fullLength = (Get-Item $file).FullName.Length

        $found = @(Find-LongFilePath -Path $TestDrive -MinimumLength $fullLength)
        $found.Path | Should -Contain (Get-Item $file).FullName
        $found.Path | Should -Not -Match '^\\\\\?'

        @(Find-LongFilePath -Path $TestDrive -MinimumLength ($fullLength + 1) | Where-Object Path -eq (Get-Item $file).FullName).Count | Should -Be 0
    }

    It 'Repair-StoppedService takes no action on a running service' {
        $result = Repair-StoppedService -Name Winmgmt
        $result.Action | Should -Be 'None'
        $result.Status | Should -Be 'Running'
    }

    It 'Repair-StoppedService writes an error for a missing service' {
        { Repair-StoppedService -Name 'NoSuchService_MergeOps' -ErrorAction Stop } | Should -Throw '*was not found*'
    }
}

Describe 'Release' {
    It 'New-ReleaseFolder copies the newest release and skips excluded folders' {
        $root = Join-Path $TestDrive 'deploy'
        $older = New-Item -ItemType Directory -Path (Join-Path $root '2024.01.01') -Force
        $older.CreationTime = (Get-Date).AddDays(-2)
        Set-Content (Join-Path $older.FullName 'stale.txt') 'old'

        $previous = New-Item -ItemType Directory -Path (Join-Path $root '2024.02.01') -Force
        $previous.CreationTime = (Get-Date).AddDays(-1)
        New-Item -ItemType Directory -Path (Join-Path $previous.FullName 'App_Data\logs'), (Join-Path $previous.FullName 'App_Config') -Force | Out-Null
        Set-Content (Join-Path $previous.FullName 'App_Config\site.config') '<config />'
        Set-Content (Join-Path $previous.FullName 'App_Data\logs\log.txt') 'log'

        $global:LASTEXITCODE = 0
        $folder = New-ReleaseFolder -DeploymentRoot $root -Release '2024.03.01' -CopyPrevious

        $folder.FullName | Should -Be (Join-Path $root '2024.03.01')
        Test-Path (Join-Path $folder.FullName 'App_Config\site.config') | Should -BeTrue
        Test-Path (Join-Path $folder.FullName 'App_Data\logs') | Should -BeFalse
        Test-Path (Join-Path $folder.FullName 'stale.txt') | Should -BeFalse
        $LASTEXITCODE | Should -Be 0
    }

    It 'New-ReleaseFolder returns the existing folder with a warning on redeploy' {
        $root = Join-Path $TestDrive 'deploy'
        $folder = New-ReleaseFolder -DeploymentRoot $root -Release '2024.03.01' -WarningVariable warnings -WarningAction SilentlyContinue
        $folder.Name | Should -Be '2024.03.01'
        $warnings | Should -Match 'already exists'
    }

    It 'Compress-ReleaseFolder keeps the newest folders and archives the rest' {
        $root = Join-Path $TestDrive 'versions'
        $archive = Join-Path $TestDrive 'archive'
        foreach ($i in 1..4) {
            $dir = New-Item -ItemType Directory -Path (Join-Path $root "v$i") -Force
            Set-Content (Join-Path $dir.FullName 'file.txt') "v$i"
            $dir.CreationTime = (Get-Date).AddDays(-10 + $i)
        }

        @(Compress-ReleaseFolder -Path $root -ArchivePath $archive -Keep 2 -WhatIf).Count | Should -Be 0
        Test-Path $archive | Should -BeFalse

        $results = @(Compress-ReleaseFolder -Path $root -ArchivePath $archive -Keep 2 -RemoveAfterArchive -Confirm:$false)

        $results.Count | Should -Be 2
        (Get-ChildItem $archive).Name | Sort-Object | Should -Be @('v1.zip', 'v2.zip')
        (Get-ChildItem $root).Name | Sort-Object | Should -Be @('v3', 'v4')
    }
}

Describe 'Sitecore' {
    It 'Clear-SitecoreBinFolder keeps allow-listed assemblies and removes the rest' {
        $site = Join-Path $TestDrive 'cm'
        $bin = Join-Path $site 'bin'
        New-Item -ItemType Directory -Path (Join-Path $bin 'roslyn') -Force | Out-Null
        foreach ($name in 'Merge.Feature.dll', 'Sitecore.Kernel.dll', 'Sitecore.Mvc.dll', 'Sitecore.Support.123.dll', 'Old.Thing.dll') {
            Set-Content (Join-Path $bin $name) 'x'
        }

        $removed = @(Clear-SitecoreBinFolder -Path $site -AdditionalKeep 'Sitecore.Kernel.*, Sitecore.Mvc.*' -Confirm:$false)

        $removed.Name | Sort-Object | Should -Be @('Old.Thing.dll', 'roslyn')
        (Get-ChildItem $bin).Name | Sort-Object | Should -Be @('Merge.Feature.dll', 'Sitecore.Kernel.dll', 'Sitecore.Mvc.dll', 'Sitecore.Support.123.dll')
    }
}

Describe 'DotNet' {
    BeforeEach {
        $script:ProjectDir = Join-Path $TestDrive ("proj" + [guid]::NewGuid().ToString('N').Substring(0, 6))
        New-Item -ItemType Directory -Path (Join-Path $ProjectDir 'Controllers') -Force | Out-Null
        Set-Content (Join-Path $ProjectDir 'Controllers\Home.cs') '// code'
        $script:ProjectPath = Join-Path $ProjectDir 'Feature.csproj'
        Set-Content $ProjectPath -Encoding UTF8 @'
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <Import Project="..\packages\Microsoft.Net.Compilers.2.4.0\build\Microsoft.Net.Compilers.props" Condition="Exists('..\packages\Microsoft.Net.Compilers.2.4.0\build\Microsoft.Net.Compilers.props')" />
  <ItemGroup>
    <Reference Include="Newtonsoft.Json, Version=13.0.0.0">
      <HintPath>..\Packages\Newtonsoft.Json.13.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
    </Reference>
    <Reference Include="System" />
    <Reference Include="System.Web" />
  </ItemGroup>
  <ItemGroup>
    <Compile Include="Controllers\Home.cs" />
    <Compile Include="Controllers\Missing.cs" />
    <Compile Include="Models\%28Generated%29.cs" />
    <Content Include="Views\**\*.cshtml" />
    <None Include="packages.config" />
  </ItemGroup>
  <Target Name="EnsureNuGetPackageBuildImports" BeforeTargets="PrepareForBuild">
    <Error Text="missing packages" />
  </Target>
</Project>
'@
        Set-Content (Join-Path $ProjectDir 'packages.config') @'
<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net48" />
  <package id="Microsoft.Net.Compilers" version="2.4.0" targetFramework="net48" developmentDependency="true" />
</packages>
'@
        $script:SolutionPath = Join-Path $TestDrive 'Website.sln'
        $relative = (Split-Path -Leaf $ProjectDir) + '\Feature.csproj'
        Set-Content $SolutionPath @"
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Feature", "$relative", "{11111111-1111-1111-1111-111111111111}"
EndProject
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "Solution Items", "Solution Items", "{22222222-2222-2222-2222-222222222222}"
EndProject
"@
    }

    It 'Find-DotNetMissingFile reports missing paths and skips references and wildcards' {
        $missing = @(Find-DotNetMissingFile -Path $ProjectPath)

        $missing.Include | Sort-Object | Should -Be @('Controllers\Missing.cs', 'Models\%28Generated%29.cs')
    }

    It 'Find-DotNetMissingFile expands solutions' {
        $missing = @(Find-DotNetMissingFile -Path $SolutionPath)
        $missing.Include | Should -Contain 'Controllers\Missing.cs'
        ($missing | Where-Object Include -like 'Models*').ExpectedPath | Should -BeLike '*Models\(Generated).cs'
    }

    It 'Remove-DotNetPackagesConfig leaves everything alone with -WhatIf' {
        $before = Get-Content $ProjectPath -Raw
        Remove-DotNetPackagesConfig -Path $ProjectPath -AddPackageReference -WhatIf
        Get-Content $ProjectPath -Raw | Should -Be $before
        Test-Path (Join-Path $ProjectDir 'packages.config') | Should -BeTrue
    }

    It 'Remove-DotNetPackagesConfig strips NuGet wiring and adds PackageReference items' {
        $result = Remove-DotNetPackagesConfig -Path $SolutionPath -AddPackageReference -Confirm:$false

        $result.ReferencesRemoved | Should -Be 1
        $result.ImportsRemoved | Should -Be 1
        $result.PackageReferencesAdded | Should -Be 2
        Test-Path (Join-Path $ProjectDir 'packages.config') | Should -BeFalse

        [xml]$xml = Get-Content $ProjectPath -Raw
        $ns = @{ m = 'http://schemas.microsoft.com/developer/msbuild/2003' }
        @(Select-Xml -Xml $xml -XPath '//m:Reference' -Namespace $ns).Node.Include | Should -Be @('System', 'System.Web')
        @(Select-Xml -Xml $xml -XPath '//m:Import' -Namespace $ns).Count | Should -Be 0
        @(Select-Xml -Xml $xml -XPath "//m:Target[@Name='EnsureNuGetPackageBuildImports']" -Namespace $ns).Count | Should -Be 0
        @(Select-Xml -Xml $xml -XPath "//m:None[@Include='packages.config']" -Namespace $ns).Count | Should -Be 0
        $packageReferences = @(Select-Xml -Xml $xml -XPath '//m:PackageReference' -Namespace $ns).Node
        $packageReferences.Include | Should -Be @('Newtonsoft.Json', 'Microsoft.Net.Compilers')
        $packageReferences[0].Version | Should -Be '13.0.1'
        Get-Content $ProjectPath -Raw | Should -Not -Match "\r?\n\s*\r?\n\s*\r?\n"
    }
}

Describe 'GitHub' {
    BeforeAll {
        $script:Repos = @(
            [pscustomobject]@{ name = 'site-a'; nameWithOwner = 'org/site-a'; visibility = 'PRIVATE'; isArchived = $false }
            [pscustomobject]@{ name = 'actions-sandbox'; nameWithOwner = 'org/actions-sandbox'; visibility = 'PRIVATE'; isArchived = $false }
            [pscustomobject]@{ name = 'old-site'; nameWithOwner = 'org/old-site'; visibility = 'PRIVATE'; isArchived = $true }
            [pscustomobject]@{ name = 'docs'; nameWithOwner = 'org/docs'; visibility = 'PUBLIC'; isArchived = $false }
        )
    }

    BeforeEach {
        Mock -ModuleName MergeOps Assert-GhCli { }
        # Mocks run in module scope, so pass the fixture through a global.
        $global:MergeOpsTestRepos = $Repos
        Mock -ModuleName MergeOps Get-GhOrgRepository { $global:MergeOpsTestRepos }
    }

    AfterAll {
        Remove-Variable -Name MergeOpsTestRepos -Scope Global -ErrorAction SilentlyContinue
    }

    It 'Set-GitHubRepoVisibility changes nothing with -WhatIf' {
        Mock -ModuleName MergeOps Invoke-GhApi { }
        $results = @(Set-GitHubRepoVisibility -Organization org -Visibility internal -Exclude 'actions-*' -WhatIf)

        $results.Repository | Should -Be @('org/site-a')
        $results[0].Status | Should -Be 'Skipped'
        Should -Invoke -ModuleName MergeOps Invoke-GhApi -Times 0
    }

    It 'Set-GitHubRepoVisibility patches only matching, non-archived, non-excluded repos' {
        Mock -ModuleName MergeOps Invoke-GhApi { }
        $results = @(Set-GitHubRepoVisibility -Organization org -Visibility internal -Exclude 'actions-*' -Confirm:$false)

        $results.Status | Should -Be @('Updated')
        Should -Invoke -ModuleName MergeOps Invoke-GhApi -Times 1 -Exactly -ParameterFilter {
            $Endpoint -eq 'repos/org/site-a' -and $Method -eq 'PATCH' -and $Field.visibility -eq 'internal'
        }
    }

    It 'Set-GitHubRepoVisibility refuses a no-op change' {
        { Set-GitHubRepoVisibility -Organization org -Visibility private -CurrentVisibility private -WhatIf } | Should -Throw '*Nothing would change*'
    }

    It 'Find-GitHubWorkflowUsage reports matching workflow files with the first matching line' {
        Mock -ModuleName MergeOps Invoke-GhApi {
            switch -Wildcard ($Endpoint) {
                '*/contents/.github/workflows' {
                    if ($Endpoint -like 'repos/org/site-a/*') {
                        @(
                            [pscustomobject]@{ name = 'build.yml'; path = '.github/workflows/build.yml' }
                            [pscustomobject]@{ name = 'README.md'; path = '.github/workflows/README.md' }
                        )
                    }
                    else {
                        throw 'Not Found'
                    }
                }
                '*/build.yml' {
                    $yaml = "name: build`njobs:`n  ci:`n    uses: org/shared/.github/workflows/frontend-ci.yml@main`n"
                    [pscustomobject]@{ content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($yaml)) }
                }
            }
        }

        $found = @(Find-GitHubWorkflowUsage -Organization org -Pattern 'frontend-ci')

        $found.Count | Should -Be 1
        $found[0].Repository | Should -Be 'org/site-a'
        $found[0].LineNumber | Should -Be 4
        $found[0].Line | Should -BeLike 'uses: org/shared*'
        Should -Invoke -ModuleName MergeOps Invoke-GhApi -Times 0 -ParameterFilter { $Endpoint -like 'repos/org/old-site/*' }
    }
}
