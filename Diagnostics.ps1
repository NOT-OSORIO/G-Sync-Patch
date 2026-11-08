#Requires -Version 5.1
# Read-only report: GPU, panel, connection, chosen preset and the table that would be applied.
# -List shows every display connected to an NVIDIA GPU.
[CmdletBinding()]
param([ValidateSet('Auto','DellValidated','Generic2023')][string]$Preset='Auto',[string]$MonitorId,[string]$GpuInstanceId,[switch]$List)
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'src/NvidiaVrrPatch.psm1') -Force
    if($List){Get-VrrConnections}else{Get-VrrPublicTarget (Get-VrrTarget -Preset $Preset -MonitorId $MonitorId -GpuInstanceId $GpuInstanceId)}
}catch{Write-Error $_;exit 1}
