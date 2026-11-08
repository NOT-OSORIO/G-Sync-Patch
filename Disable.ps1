#Requires -Version 5.1
# Disables the patch: restores the original RMemNBSItable value from the backup (or removes the
# value if it did not exist before). -WhatIf shows what would be done.
[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$GpuInstanceId,[switch]$Pause)
$ErrorActionPreference='Stop'
$exitCode=0
try {
    Import-Module (Join-Path $PSScriptRoot 'src/NvidiaVrrPatch.psm1') -Force
    if(-not(Test-VrrAdministrator) -and -not $WhatIfPreference){
        $arguments=@('-NoProfile','-File',('"'+$PSCommandPath+'"'))
        if($GpuInstanceId){if($GpuInstanceId -match '["\r\n]'){throw 'Invalid ID.'};$arguments+=@('-GpuInstanceId',('"'+$GpuInstanceId+'"'))}
        if($Pause){$arguments+='-Pause'}
        $exe=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $child=Start-Process -FilePath $exe -ArgumentList $arguments -Verb RunAs -WindowStyle Normal -Wait -PassThru
        $exitCode=$child.ExitCode
        $Pause=$false
    }else{Uninstall-VrrPatch -GpuInstanceId $GpuInstanceId -LegacyFolder (Join-Path $PSScriptRoot 'original-backup') -WhatIf:$WhatIfPreference}
}catch{Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red;$exitCode=1}
if($Pause){Read-Host 'Press Enter to close'|Out-Null}
exit $exitCode
