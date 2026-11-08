#Requires -Version 5.1
# Enables G-SYNC on the internal (eDP) panel: writes the platform table to RMemNBSItable,
# keeping a backup of the original value first. -CheckOnly shows what would be done.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$CheckOnly,
    [ValidateSet('Auto','DellValidated','Generic2023')][string]$Preset='Auto',
    [string]$MonitorId,
    [string]$GpuInstanceId,
    [string]$ImportBackup,
    [switch]$Pause
)
$ErrorActionPreference='Stop'
$exitCode=0
try {
    Import-Module (Join-Path $PSScriptRoot 'src/NvidiaVrrPatch.psm1') -Force
    $target=Get-VrrTarget -Preset $Preset -MonitorId $MonitorId -GpuInstanceId $GpuInstanceId
    Get-VrrPublicTarget $target|Format-List|Out-Host
    if(-not $target.PhysicallyValidated){Write-Warning 'This combination of preset, hardware and driver has no recorded physical validation. The generic format was only validated offline.'}
    if(-not $target.DriverTested){Write-Warning 'This driver version has not been validated.'}
    if($CheckOnly){Write-Output 'Check only: registry and backups were left untouched.'}
    elseif($PSCmdlet.ShouldProcess($target.Gpu,('Apply the platform table for '+$target.MonitorId))){
        if(-not(Test-VrrAdministrator)){
            $arguments=@('-NoProfile','-File',('"'+$PSCommandPath+'"'),'-Preset',$Preset)
            foreach($pair in @(@('MonitorId',$MonitorId),@('GpuInstanceId',$GpuInstanceId),@('ImportBackup',$ImportBackup))){
                if($pair[1]){if($pair[1] -match '["\r\n]'){throw 'Invalid argument.'};$arguments+=('-'+$pair[0]);$arguments+=('"'+$pair[1]+'"')}
            }
            if($Pause){$arguments+='-Pause'}
            $exe=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
            $child=Start-Process -FilePath $exe -ArgumentList $arguments -Verb RunAs -WindowStyle Normal -Wait -PassThru
            $exitCode=$child.ExitCode
            $Pause=$false
        }else{Install-VrrPatch -Target $target -ImportBackup $ImportBackup -LegacyFolder (Join-Path $PSScriptRoot 'original-backup')}
    }
}catch{Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red;$exitCode=1}
if($Pause){Read-Host 'Press Enter to close'|Out-Null}
exit $exitCode
