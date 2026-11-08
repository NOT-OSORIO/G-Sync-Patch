Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:ClassGuid='{4d36e968-e325-11ce-bfc1-08002be10318}'
$script:ValueName='RMemNBSItable'

function Initialize-VrrRuntime {
    if([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess){throw 'Use Windows and 64-bit PowerShell.'}
    if(-not ('NvidiaVrrPatch.Native' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Native.cs')}
}
function Get-VrrHash([byte[]]$Bytes) {
    $hasher=[Security.Cryptography.SHA256]::Create()
    try {return ([BitConverter]::ToString($hasher.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}
    finally {$hasher.Dispose()}
}
function Get-VrrMachineFingerprint {
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Cryptography')
    try {$id=[string]$key.GetValue('MachineGuid');if(-not $id){throw 'MachineGuid is not available.'}}
    finally {$key.Dispose()}
    return Get-VrrHash ([Text.Encoding]::UTF8.GetBytes($id))
}
function Get-VrrStateRoot {
    return Join-Path (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'NvidiaVrrPatch') (Get-VrrMachineFingerprint)
}
function Test-VrrAdministrator {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Resolve-VrrGpuKey([string]$GpuInstanceId) {
    if($GpuInstanceId -notmatch '^PCI\\VEN_10DE&DEV_[0-9A-F]{4}&SUBSYS_[0-9A-F]{8}[^\\]*\\[^\\]+$'){throw 'Invalid NVIDIA instance ID.'}
    $device=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Enum\'+$GpuInstanceId)
    if(-not $device){throw 'The GPU from the backup is not registered on this machine.'}
    try {$driver=[string]$device.GetValue('Driver')}finally{$device.Dispose()}
    if($driver -notmatch ('^'+[regex]::Escape($script:ClassGuid)+'\\[0-9]{4}$')){throw 'Unexpected class key.'}
    $path='SYSTEM\CurrentControlSet\Control\Class\'+$driver
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($path)
    if(-not $key){throw 'Driver key not found.'}
    try {
        $matching=[string]$key.GetValue('MatchingDeviceId')
        if($matching -notlike '*ven_10de*'){throw 'The registered driver is not an NVIDIA driver.'}
        return [pscustomobject]@{Path=$path;ClassDriver=$driver;DriverVersion=[string]$key.GetValue('DriverVersion');Description=[string]$key.GetValue('DriverDesc')}
    }finally{$key.Dispose()}
}
function Get-VrrSnapshot([string]$Path) {
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path)
    if(-not $key){throw 'Driver key is not available.'}
    try {
        if($key.GetValueNames() -notcontains $script:ValueName){return [pscustomobject]@{Exists=$false;Kind=$null;Base64=$null;Hash=$null}}
        $kind=$key.GetValueKind($script:ValueName).ToString()
        if($kind -ne 'Binary'){throw 'The existing RMemNBSItable is not REG_BINARY; nothing was changed.'}
        [byte[]]$bytes=$key.GetValue($script:ValueName)
        return [pscustomobject]@{Exists=$true;Kind=$kind;Base64=[Convert]::ToBase64String($bytes);Hash=(Get-VrrHash $bytes)}
    }finally{$key.Dispose()}
}
function Set-VrrRegistryBinary([string]$Path,[byte[]]$Bytes) {
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path,$true)
    if(-not $key){throw 'Target key is not available for writing.'}
    try {$key.SetValue($script:ValueName,$Bytes,[Microsoft.Win32.RegistryValueKind]::Binary)}finally{$key.Dispose()}
}
function Remove-VrrRegistryValue([string]$Path) {
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path,$true)
    if(-not $key){throw 'Target key is not available for restoring.'}
    try {$key.DeleteValue($script:ValueName,$false)}finally{$key.Dispose()}
}
function Get-VrrTarget {
    param([string]$GpuInstanceId,[string]$MonitorId,[ValidateSet('Auto','DellValidated','Generic2023')][string]$Preset='Auto')
    Initialize-VrrRuntime
    $connections=@([NvidiaVrrPatch.Native]::Connections())
    if(-not $connections.Count){throw 'No active display is connected directly to the NVIDIA GPU. Check the MUX / dedicated GPU mode; this script does not change the MUX.'}
    $wmi=@(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorConnectionParams | Where-Object Active)
    $eligible=@($connections | Where-Object {
        $connection=$_
        @($wmi|Where-Object {($_.InstanceName -replace '_[0-9]+$','') -ieq $connection.MonitorId -and $_.VideoOutputTechnology -eq 11}).Count -eq 1
    })
    if($MonitorId){$eligible=@($eligible|Where-Object MonitorId -ieq $MonitorId)}
    if($eligible.Count -ne 1){throw 'Did not find exactly one active eDP display on the NVIDIA GPU. Run Diagnostics.ps1 -List; if there is more than one, pass -MonitorId.'}
    $connection=$eligible[0]
    $gpus=@(Get-PnpDevice -Class Display -PresentOnly | Where-Object {$_.InstanceId.StartsWith($connection.AdapterId+'\',[StringComparison]::OrdinalIgnoreCase)})
    if($GpuInstanceId){$gpus=@($gpus|Where-Object InstanceId -ieq $GpuInstanceId)}
    if($gpus.Count -ne 1){throw 'GPU is ambiguous or was not found. Pass -GpuInstanceId with the exact instance.'}
    $gpu=$gpus[0]
    if($gpu.Status -ne 'OK'){throw 'The GPU status is not OK.'}
    $keyInfo=Resolve-VrrGpuKey $gpu.InstanceId
    $match=[regex]::Match($gpu.InstanceId,'VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})&SUBSYS_([0-9A-F]{4})([0-9A-F]{4})','IgnoreCase')
    if(-not $match.Success){throw 'Incomplete PCI IDs.'}
    $gpuFields=($match.Groups[1].Value+$match.Groups[2].Value+$match.Groups[4].Value+$match.Groups[3].Value).ToUpperInvariant()
    $edidKey=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Enum\'+$connection.MonitorId+'\Device Parameters')
    if(-not $edidKey){throw 'EDID of the connected display is not available.'}
    try {[byte[]]$edid=$edidKey.GetValue('EDID')}finally{$edidKey.Dispose()}
    if($edid.Length -lt 128 -or [Convert]::ToBase64String($edid[0..7]) -ne 'AP///////wA='){throw 'Invalid EDID header.'}
    $blocks=1+[int]$edid[126]
    if($edid.Length -lt 128*$blocks){throw 'Truncated EDID.'}
    for($block=0;$block -lt $blocks;$block++){
        $sum=0;for($i=0;$i -lt 128;$i++){$sum+=$edid[$block*128+$i]}
        if(($sum -band 255) -ne 0){throw 'Invalid EDID checksum.'}
    }
    if(($edid[20] -band 128) -eq 0){throw 'Analog EDID input is not supported.'}
    $manufacturer=[BitConverter]::ToUInt16($edid,8);$product=[BitConverter]::ToUInt16($edid,10)
    if($manufacturer -eq 0 -or $product -eq 0){throw 'Incomplete panel IDs.'}
    $known=$false
    if($gpuFields -eq '10DE25EC10280BF8' -and $manufacturer -eq 0xAE0D -and $product -eq 0x1522){
        $bridge=@(Get-PnpDevice -PresentOnly|Where-Object InstanceId -like 'PCI\VEN_8086&DEV_A719&SUBSYS_0BF81028*')
        $known=$bridge.Count -eq 1
    }
    if($Preset -eq 'DellValidated' -and -not $known){throw 'This hardware does not match the validated Dell preset.'}
    if($Preset -eq 'Auto'){if($known){$Preset='DellValidated'}else{$Preset='Generic2023'}}
    $platform='';if($Preset -eq 'DellValidated'){$platform='8086A71910280BF8'}
    [byte[]]$binary=[NvidiaVrrPatch.Native]::BuildTable($Preset,$gpuFields,$manufacturer,$product,$platform)
    $snapshot=Get-VrrSnapshot $keyInfo.Path
    return [pscustomobject]@{
        GpuInstanceId=$gpu.InstanceId;Gpu=$keyInfo.Description;DriverVersion=$keyInfo.DriverVersion
        DriverTested=($keyInfo.DriverVersion -eq '32.0.16.2114');MonitorId=$connection.MonitorId
        ManufacturerRaw=('0x{0:X4}' -f $manufacturer);Product=('0x{0:X4}' -f $product)
        Connection='eDP directly on the NVIDIA GPU';Preset=$Preset;PhysicallyValidated=($Preset -eq 'DellValidated' -and $keyInfo.DriverVersion -eq '32.0.16.2114')
        RegistryPath=$keyInfo.Path;GpuFields=$gpuFields;EdidSha256=(Get-VrrHash $edid)
        Binary=$binary;Sha256=(Get-VrrHash $binary);Current=$snapshot
    }
}
function Get-VrrConnections {
    Initialize-VrrRuntime
    $connections=@([NvidiaVrrPatch.Native]::Connections())
    $gpus=@(Get-PnpDevice -Class Display -PresentOnly)
    $wmi=@(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorConnectionParams|Where-Object Active)
    foreach($connection in $connections){
        $ids=@($gpus|Where-Object {$_.InstanceId.StartsWith($connection.AdapterId+'\',[StringComparison]::OrdinalIgnoreCase)}|Select-Object -ExpandProperty InstanceId)
        $monitors=@($wmi|Where-Object {($_.InstanceName -replace '_[0-9]+$','') -ieq $connection.MonitorId})
        [pscustomobject]@{Gpu=$connection.Description;GpuInstanceIds=$ids;MonitorId=$connection.MonitorId;VideoOutputTechnology=@($monitors|Select-Object -ExpandProperty VideoOutputTechnology);EdpEligible=(@($monitors|Where-Object VideoOutputTechnology -eq 11).Count -eq 1)}
    }
}
function Get-VrrPublicTarget($Target) {
    return $Target|Select-Object Gpu,GpuInstanceId,DriverVersion,DriverTested,MonitorId,ManufacturerRaw,Product,Connection,Preset,PhysicallyValidated,RegistryPath,Sha256,@{n='Bytes';e={$_.Binary.Length}},@{n='TableExists';e={$_.Current.Exists}},@{n='AlreadyMatches';e={$_.Current.Hash -eq $_.Sha256}}
}
function New-VrrBackupRecord($Target,$Snapshot,[string]$MachineFingerprint) {
    return [pscustomobject][ordered]@{SchemaVersion=1;MachineFingerprint=$MachineFingerprint;GpuInstanceId=$Target.GpuInstanceId;RegistryPath=$Target.RegistryPath;ValueName=$script:ValueName;MonitorId=$Target.MonitorId;Preset=$Target.Preset;DriverVersion=$Target.DriverVersion;CreatedUtc=[DateTime]::UtcNow.ToString('o');State='Prepared';Original=$Snapshot;AppliedSha256=$Target.Sha256}
}
function Get-VrrRestoreDecision($Backup,$Current,[string]$MachineFingerprint) {
    if($Backup.SchemaVersion -ne 1 -or $Backup.MachineFingerprint -ne $MachineFingerprint -or $Backup.ValueName -ne $script:ValueName){throw 'The backup is incompatible or comes from another computer.'}
    if($Backup.Original.Exists -isnot [bool]){throw 'Invalid original state.'}
    if($Backup.Original.Exists){
        if($Backup.Original.Kind -ne 'Binary'){throw 'Unsupported original value type.'}
        [byte[]]$originalBytes=[Convert]::FromBase64String($Backup.Original.Base64)
        if((Get-VrrHash $originalBytes) -ne $Backup.Original.Hash){throw 'The original backup failed its integrity check.'}
    }elseif($null -ne $Backup.Original.Base64 -or $null -ne $Backup.Original.Hash){throw 'Inconsistent backup of an absent value.'}
    if($Current.Exists -eq $Backup.Original.Exists -and $Current.Base64 -ceq $Backup.Original.Base64){return 'AlreadyOriginal'}
    if(-not $Current.Exists -and -not $Backup.Original.Exists){return 'AlreadyOriginal'}
    if(-not $Current.Exists -or $Current.Hash -ne $Backup.AppliedSha256){throw 'The current value changed after activation. It will not be overwritten; see the troubleshooting guide.'}
    if($Backup.Original.Exists){return 'RestoreBinary'}else{return 'RemoveValue'}
}
function Initialize-VrrStateDirectory {
    $root=Get-VrrStateRoot
    New-Item -ItemType Directory -Path $root -Force|Out-Null
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach($sidText in @('S-1-5-18','S-1-5-32-544')){
        $sid=New-Object Security.Principal.SecurityIdentifier($sidText)
        $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $root -AclObject $acl
    return $root
}
function Save-VrrState([string]$Path,$Record,[switch]$Create) {
    $temp=$Path+'.new-'+[Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temp,($Record|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
    try {if($Create){[IO.File]::Move($temp,$Path)}else{[IO.File]::Replace($temp,$Path,[NullString]::Value)}}
    finally {if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
# Backup of the original value made by an earlier manual procedure (JSON with Key, Name, Existed,
# OriginalBase64, AppliedSha256), kept in an 'original-backup' folder next to the scripts:
# returns the first one that matches the driver key and the table applied right now.
function Find-VrrLegacyBackup([string]$Folder,$Target,$Current) {
    if(-not $Folder -or -not (Test-Path -LiteralPath $Folder -PathType Container) -or -not $Current.Exists){return $null}
    $expectedKey='Registry::HKEY_LOCAL_MACHINE\'+$Target.RegistryPath
    foreach($file in @(Get-ChildItem -LiteralPath $Folder -File -Filter '*.json')){
        try {$legacy=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json}catch{continue}
        if($legacy.PSObject.Properties['Key'] -and $legacy.Key -ieq $expectedKey -and $legacy.Name -eq $script:ValueName -and $legacy.AppliedSha256 -ieq $Current.Hash){return $file.FullName}
    }
    return $null
}
function Install-VrrPatch {
    param($Target,[string]$ImportBackup,[string]$LegacyFolder)
    if(-not(Test-VrrAdministrator)){throw 'Enabling requires administrator rights.'}
    $root=Initialize-VrrStateDirectory
    $fingerprint=Get-VrrMachineFingerprint
    $name=(Get-VrrHash ([Text.Encoding]::UTF8.GetBytes($Target.GpuInstanceId.ToUpperInvariant())))+'.json'
    $path=Join-Path $root $name
    $current=Get-VrrSnapshot $Target.RegistryPath
    if(Test-Path -LiteralPath $path){
        $backup=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if($backup.MachineFingerprint -ne $fingerprint -or $backup.GpuInstanceId -ine $Target.GpuInstanceId -or $backup.ValueName -ne $script:ValueName){throw 'The existing backup does not match the target.'}
        if($current.Hash -eq $backup.AppliedSha256 -and $current.Hash -eq $Target.Sha256){
            $null=Get-VrrRestoreDecision $backup $current $fingerprint
            Write-Output 'Already enabled. The original backup is preserved.';return
        }
        throw 'A backup exists and the current state is different. Disable before applying another configuration.'
    }
    $original=$current
    if($current.Exists -and -not $ImportBackup){
        $ImportBackup=Find-VrrLegacyBackup $LegacyFolder $Target $current
        if($ImportBackup){Write-Output ('Backup from the earlier procedure found and imported: '+$ImportBackup)}
    }
    if($current.Exists){
        if(-not $ImportBackup){throw 'RMemNBSItable already exists and there is no backup of its original value. No table will be replaced. See "Troubleshooting" in the README.'}
        $legacy=Get-Content -LiteralPath $ImportBackup -Raw|ConvertFrom-Json
        $expectedKey='Registry::HKEY_LOCAL_MACHINE\'+$Target.RegistryPath
        if($legacy.Key -ine $expectedKey -or $legacy.Name -ne $script:ValueName -or $legacy.AppliedSha256 -ine $current.Hash -or $current.Hash -ne $Target.Sha256){throw 'The imported backup does not match the current key and table.'}
        if($legacy.Existed -isnot [bool]){throw 'Invalid legacy backup.'}
        if($legacy.Existed){
            [byte[]]$old=[Convert]::FromBase64String($legacy.OriginalBase64)
            $original=[pscustomobject]@{Exists=$true;Kind='Binary';Base64=[Convert]::ToBase64String($old);Hash=(Get-VrrHash $old)}
        }else{$original=[pscustomobject]@{Exists=$false;Kind=$null;Base64=$null;Hash=$null}}
    }elseif($ImportBackup){throw 'Importing requires the matching table to be applied; nothing was changed.'}
    $backup=New-VrrBackupRecord $Target $original $fingerprint
    Save-VrrState $path $backup -Create
    if($current.Hash -ne $Target.Sha256){
        Set-VrrRegistryBinary $Target.RegistryPath ([byte[]]$Target.Binary)
    }
    if((Get-VrrSnapshot $Target.RegistryPath).Hash -ne $Target.Sha256){throw 'Write verification failed. The backup is kept in ProgramData.'}
    $backup.State='Active';Save-VrrState $path $backup
    Write-Output ('Enabled. Backup: '+$path)
    Write-Output 'Restart Windows, then open NVIDIA Control Panel > Set up G-SYNC. Nothing was restarted automatically.'
}
function Uninstall-VrrPatch {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$GpuInstanceId,[string]$LegacyFolder)
    if(-not(Test-VrrAdministrator) -and -not $WhatIfPreference){throw 'Disabling requires administrator rights.'}
    $root=Get-VrrStateRoot
    $list={
        $files=@();if(Test-Path -LiteralPath $root){$files=@(Get-ChildItem -LiteralPath $root -File -Filter '*.json')}
        @(foreach($file in $files){$backup=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json;if(-not $GpuInstanceId -or $backup.GpuInstanceId -ieq $GpuInstanceId){[pscustomobject]@{File=$file.FullName;Backup=$backup}}})
    }
    $items=@(& $list)
    if($items.Count -eq 0 -and $LegacyFolder -and (Test-Path -LiteralPath $LegacyFolder -PathType Container)){
        # enabled by the earlier procedure: register its backup, then restore as usual
        $target=Get-VrrTarget -GpuInstanceId $GpuInstanceId
        $legacy=Find-VrrLegacyBackup $LegacyFolder $target (Get-VrrSnapshot $target.RegistryPath)
        if($legacy){
            if($WhatIfPreference){Write-Output ('Would import the backup from the earlier procedure ('+$legacy+') and restore the original value.');return}
            $null=Install-VrrPatch -Target $target -ImportBackup $legacy
            Write-Output ('Backup from the earlier procedure imported: '+$legacy)
            $items=@(& $list)
        }
    }
    if($items.Count -eq 0){Write-Output 'This computer has no managed activation. Nothing was changed.';return}
    if($items.Count -ne 1){throw 'More than one GPU has a backup. Pass -GpuInstanceId.'}
    $item=$items[0];$backup=$item.Backup
    $keyInfo=Resolve-VrrGpuKey $backup.GpuInstanceId
    $current=Get-VrrSnapshot $keyInfo.Path
    $decision=Get-VrrRestoreDecision $backup $current (Get-VrrMachineFingerprint)
    if(-not $PSCmdlet.ShouldProcess($keyInfo.Description,('Restore RMemNBSItable: '+$decision))){return}
    if($decision -ne 'AlreadyOriginal'){
        if($decision -eq 'RestoreBinary'){Set-VrrRegistryBinary $keyInfo.Path ([Convert]::FromBase64String($backup.Original.Base64))}
        else{Remove-VrrRegistryValue $keyInfo.Path}
    }
    $after=Get-VrrSnapshot $keyInfo.Path
    if($after.Exists -ne $backup.Original.Exists -or $after.Base64 -cne $backup.Original.Base64){throw 'Restore verification failed; the backup is kept.'}
    $backup.State='Restored';Save-VrrState $item.File $backup
    $history=Join-Path $root 'history';New-Item -ItemType Directory -Path $history -Force|Out-Null
    Move-Item -LiteralPath $item.File -Destination (Join-Path $history ((Split-Path $item.File -Leaf)+'.'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')+'-'+[Guid]::NewGuid().ToString('N')+'.json'))
    Write-Output 'Original state restored and backup archived. Restart Windows. Nothing was restarted automatically.'
}
Export-ModuleMember -Function Get-VrrTarget,Get-VrrConnections,Get-VrrPublicTarget,Test-VrrAdministrator,Install-VrrPatch,Uninstall-VrrPatch
