<#
.SYNOPSIS
Prepare a LOCAL Hyper-V Based Skype for Business LAB (2 separate: 2015 + 2019) incl. Exchange and Office Online Services

.DESCRIPTION
As of now, the Base is build on:
- creating separated private Networks for each LAB
- creating defferentiating vhdx based on Widnows Server 2019 base image. (reducing space needed)
- attaching VM's to the right Network
- attaching the right ISO Files for each System (Exchange, SQL, SfB + Windows Server ISO)
In my case the base VHDX File is in GERMAN, but you can always build your own and exchange in: $ParentPath.
.EXAMPLE
Building a Full BASE Infrastructure for Skype for Business 2015/2019:
All VM's based on Windows Server 2019:
- Domain Controller
- 3* Skype for Business Frontend Server
- SQL Server
- Exchange Server
- Office Online Server
- Client

VM's have Differentating VHDX Files (based on VHDX dated from: end of 2021) to reduce Space amount.
All VM's bound into one Network.

ToDo:
Domain Setup
SFB, SQL, Exchange and OOS install + setup
User/data propagation

.NOTES
	v0.1
	Author: Pawel Kostelnik
	Authored date: September, 08, 2022
	
#>

Import-Module Hyper-V

# Variablecleanup
$VMPrefix = ""
$VMSwitchName = ""
$VMPath = ""
$ISOPath = ""
$ISO = ""
$sfbiso = ""
$exiso = ""
$sqliso = ""
$oosiso = ""
$ParentPath = ""
$VMList = ""
$VM = ""

### Skype for Business 2015 (3*FE+SQL) + Exchange + Office Web App Server

#Variables to differentiate different LABS
$VMPrefix = "sfb15"
$VMSwitchName = "x-$VMPrefix"
$VMPath = "E:\Hyper-V"
$ISOPath = "F:\iso\VS(MSDN)"
$ISO = "Windows Server\de-de_windows_server_2019_updated_aug_2021_x64_dvd_a11b80c3.iso" #Windows Server 2019
$sfbiso = "Skype for Business\de_skype_for_business_server_2015_x64_dvd_6622057.iso" #Skype for Business 2015
$exiso = "Exchange\mul_exchange_server_2016_cumulative_update_23_x64_dvd_a7c5e6ee.iso" #Exchange Server 2016
$sqliso = "SQL\de_sql_server_2016_enterprise_with_service_pack_2_x64_dvd_12119061.iso" #SQL Server 2016
$oosiso = "de_office_online_server_last_updated_november_2018_x64_dvd_e1b74239.iso" #Office Online Server
$ParentPath = "D:\Hyper-V\base\WS_2019_18.09.22.vhdx" #Windows Server 2019 Base Image (Updated: September, 18, 2022)

# commented because of my VM Networking Setup
#Remove-VMSwitch -Name $VMSwitchName -Force
#New-VMSwitch -Name $VMSwitchName -SwitchType Private -Notes "Switch for Skype for Business 2015 Lab named: $VMSwitchName" 

$VMList = "$VMPrefix-LAB-DC",`
"$VMPrefix-LAB-$VMPrefix-1",`"$VMPrefix-LAB-$VMPrefix-2",`"$VMPrefix-LAB-$VMPrefix-3",`"$VMPrefix-LAB-SQL",`"$VMPrefix-LAB-Exchange",`"$VMPrefix-LAB-oos",`"$VMPrefix-LAB-Client"

ForEach ($VM in $VMList) {
New-VHD -Path "$VMPath\$VM\$VM.vhdx" `-Differencing `-ParentPath $ParentPathNew-VM -Name $VM `-Generation 2 `-MemoryStartupBytes 2GB `-VHDPath "$VMPath\$VM\$VM.vhdx" `-SwitchName $VMSwitchName `-GuestStateIsolationType 'TrustedLaunch'
Set-VM -Name $VM `-ProcessorCount 2 `-DynamicMemory `-MemoryMaximumBytes 16GB `-AutomaticStartAction Nothing `-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `-Path "$ISOPath\$ISO"Set-VMFirmware -VMName $VM -EnableSecureBoot On `-FirstBootDevice ((Get-VMFirmware -VMName $VM).BootOrder | 
? Device -like *DvD*).Device}

# SQL
Set-VM -Name "$VMPrefix-LAB-SQL" `-ProcessorCount 4 `-DynamicMemory `-MemoryMaximumBytes 32GB `-AutomaticStartAction Nothing `-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-SQL" `-Path "$ISOPath\$SQLISO"
# Exchange
Set-VM -Name "$VMPrefix-LAB-Exchange" `-ProcessorCount 4 `-DynamicMemory `-MemoryMaximumBytes 32GB `-AutomaticStartAction Nothing `-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-Exchange" `-Path "$ISOPath\$EXISO"
# Skype For Business
$VMList = "$VMPrefix-LAB-$VMPrefix-1",`"$VMPrefix-LAB-$VMPrefix-2",`"$VMPrefix-LAB-$VMPrefix-3"
ForEach ($VM in $VMList) {Set-VM -Name $VM `-ProcessorCount 2 `-DynamicMemory `-MemoryMaximumBytes 24GB `-AutomaticStartAction Nothing `-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `-Path "$ISOPath\$sfbISO"
}
# Office Online Server
Set-VM -Name "$VMPrefix-LAB-oos" `-ProcessorCount 2 `-DynamicMemory `-MemoryMaximumBytes 16GB `-AutomaticStartAction Nothing `-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-oos" `-Path "$ISOPath\$OOSISO"

# Variablecleanup
$VMPrefix = ""
$VMSwitchName = ""
$VMPath = ""
$ISOPath = ""
$ISO = ""
$sfbiso = ""
$exiso = ""
$sqliso = ""
$oosiso = ""
$ParentPath = ""
$VMList = ""
$VM = ""

### Skype for Business 2019 (3*FE+SQL) + Exchange + Office Online Server

$VMPrefix = "sfb19"
$VMSwitchName = "x-$VMPrefix"
$VMPath = "E:\Hyper-V"
$ISOPath = "F:\iso\VS(MSDN)"
$ISO = "Windows Server\de-de_windows_server_2019_updated_aug_2021_x64_dvd_a11b80c3.iso"
$sfbiso = "Skype for Business\de_skype_for_business_server_2019_x64_dvd_da7675e1.iso"
$exiso = "Exchange\mul_exchange_server_2019_cumulative_update_12_x64_dvd_52bf3153.iso"
$sqliso = "SQL\de_sql_server_2019_enterprise_x64_dvd_25add11c.iso"
$oosiso = "de_office_online_server_last_updated_november_2018_x64_dvd_e1b74239.iso"
$ParentPath = "D:\Hyper-V\base\WS_2019_18.09.22.vhdx" #Windows Server 2019 Base Image (Updated: September, 18, 2022)

# commented because of my VM Networking Setup
#Remove-VMSwitch -Name $VMSwitchName -Force
#New-VMSwitch -Name $VMSwitchName -SwitchType Private -Notes "Switch for Skype for Business 2019 Lab named: $VMSwitchName" 

$VMList = "$VMPrefix-LAB-DC",`
"$VMPrefix-LAB-$VMPrefix-1",`"$VMPrefix-LAB-$VMPrefix-2",`"$VMPrefix-LAB-$VMPrefix-3",`"$VMPrefix-LAB-SQL",`"$VMPrefix-LAB-Exchange",`"$VMPrefix-LAB-oos",`"$VMPrefix-LAB-Client"

ForEach ($VM in $VMList) {
New-VHD -Path "$VMPath\$VM\$VM.vhdx" `-Differencing `-ParentPath $ParentPathNew-VM -Name $VM `-Generation 2 `-MemoryStartupBytes 2GB `-VHDPath "$VMPath\$VM\$VM.vhdx" `-SwitchName $VMSwitchName `-GuestStateIsolationType 'TrustedLaunch'
Set-VM -Name $VM `-ProcessorCount 2 `-DynamicMemory `-MemoryMaximumBytes 16GB `-AutomaticStartAction Nothing `-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `-Path "$ISOPath\$ISO"Set-VMFirmware -VMName $VM -EnableSecureBoot On `-FirstBootDevice ((Get-VMFirmware -VMName $VM).BootOrder | 
? Device -like *DvD*).Device}

# SQL
Set-VM -Name "$VMPrefix-LAB-SQL" `-ProcessorCount 4 `-DynamicMemory `-MemoryMaximumBytes 32GB `-AutomaticStartAction Nothing `-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-SQL" `-Path "$ISOPath\$SQLISO"
# Exchange
Set-VM -Name "$VMPrefix-LAB-Exchange" `-ProcessorCount 4 `-DynamicMemory `-MemoryMaximumBytes 32GB `-AutomaticStartAction Nothing `-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-Exchange" `-Path "$ISOPath\$EXISO"
# Skype For Business
$VMList = "$VMPrefix-LAB-$VMPrefix-1",`"$VMPrefix-LAB-$VMPrefix-2",`"$VMPrefix-LAB-$VMPrefix-3"
ForEach ($VM in $VMList) {Set-VM -Name $VM `-ProcessorCount 2 `-DynamicMemory `-MemoryMaximumBytes 24GB `-AutomaticStartAction Nothing `-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `-Path "$ISOPath\$sfbISO"
}
# Office Online Server
Set-VM -Name "$VMPrefix-LAB-oos" `-ProcessorCount 2 `-DynamicMemory `-MemoryMaximumBytes 16GB `-AutomaticStartAction Nothing `-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-oos" `-Path "$ISOPath\$OOSISO"

# Variablecleanup
$VMPrefix = ""
$VMSwitchName = ""
$VMPath = ""
$ISOPath = ""
$ISO = ""
$sfbiso = ""
$exiso = ""
$sqliso = ""
$oosiso = ""
$ParentPath = ""
$VMList = ""
$VM = ""

### Example VM Creation
# $VMName = "VMNAME"
# $VMPath = "E:\Hyper-V"
# $VM = @{
#     Name = $VMName
#     MemoryStartupBytes = 2GB
#     Generation = 2
#     NewVHDPath = "$VMPath\$VMName\$VMName.vhdx"
#     NewVHDSizeBytes = 60GB
#     BootDevice = "VHD"
#     Path = "$VMPath\$VMName"
#     SwitchName = $VMSwitchname
# }
# New-VM @VM

### Example multiple named VM Creation
#$VMPath = "E:\Hyper-V"
#'Server001','Server002','Server003' |
#ForEach-Object {
#New-VM `
#-Name $_ `
#-Generation '2' `
#-MemoryStartupBytes 2GB `
#-NewVHDPath "$VMPath\$_.vhdx" `
#-NewVHDSizeBytes 60GB `
#-SwitchName 'Default Switch' 
#}