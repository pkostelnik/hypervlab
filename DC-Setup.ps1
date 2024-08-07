#
# Windows PowerShell-Skript für AD DS-Bereitstellung
#

$Domain = "rmt22.lab"
$NetBIOS = "rmt22"
$Safemodepass = "PhaggyK26"
$SecureSafeMmodePass = ConvertTo-SecureString $Safemodepass -AsPlainText -Force

Install-WindowsFeature AD-Domain-Services -IncludeAllSubFeature -IncludeManagementTools

Import-Module ADDSDeployment
Install-ADDSForest `
-CreateDnsDelegation:$false `
-DatabasePath "C:\Windows\NTDS" `
-DomainMode "WinThreshold" `
-DomainName $Domain `
-DomainNetbiosName $NetBIOS `
-ForestMode "WinThreshold" `
-InstallDns:$true `
-LogPath "C:\Windows\NTDS" `
-NoRebootOnCompletion:$false `
-SysvolPath "C:\Windows\SYSVOL" `
-SafeModeAdministratorPassword $SecureSafeMmodePass `
-Force:$true

