function Repair-StoppedService {
    <#
    .SYNOPSIS
    Starts any of the named Windows services that are not running.

    .DESCRIPTION
    Checks each service and starts it if it is not in the Running state, then waits for it to report Running. Intended for
    scheduled health checks on IIS and Solr hosts. Starting a service requires an elevated session.

    .PARAMETER Name
    Service names. Wildcards are supported.

    .PARAMETER TimeoutSec
    How long to wait for a started service to reach Running.

    .EXAMPLE
    Repair-StoppedService -Name W3SVC, WAS

    .EXAMPLE
    Repair-StoppedService -Name 'solr-*' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$Name,

        [int]$TimeoutSec = 30
    )

    process {
        foreach ($serviceName in $Name) {
            $services = @(Get-Service -Name $serviceName -ErrorAction SilentlyContinue)
            if ($services.Count -eq 0) {
                Write-Error "Service '$serviceName' was not found."
                continue
            }

            foreach ($service in $services) {
                $initialStatus = $service.Status
                $action = 'None'

                if ($initialStatus -ne 'Running') {
                    if ($PSCmdlet.ShouldProcess($service.Name, 'Start service')) {
                        try {
                            Start-Service -InputObject $service -ErrorAction Stop
                            $service.WaitForStatus('Running', [TimeSpan]::FromSeconds($TimeoutSec))
                            $action = 'Started'
                        }
                        catch {
                            $action = 'Failed'
                            Write-Error "Could not start service '$($service.Name)': $($_.Exception.Message)"
                        }
                        $service.Refresh()
                    }
                    else {
                        $action = 'Skipped'
                    }
                }

                [pscustomobject]@{
                    Name          = $service.Name
                    DisplayName   = $service.DisplayName
                    InitialStatus = $initialStatus
                    Status        = $service.Status
                    Action        = $action
                }
            }
        }
    }
}
