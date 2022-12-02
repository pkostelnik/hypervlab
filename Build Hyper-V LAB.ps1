<#
.SYNOPSIS
Prepare a LOCAL Hyper-V Based LAB:
 * Skype for Business 2015
 * Skype for Business 2019
 * Exchange 2013
 * Exchange 2016
 * Exchange 2019

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
	
Labs in Functions:
 * sfb2015-lab
 * sfb2019-lab
 * ex2013-lab
 * ex2016-lab
 * ex2019-lab

#>

Import-Module Hyper-V
Add-Type -assembly System.Windows.Forms
Add-Type -AssemblyName PresentationFramework

<#
$main_form = New-Object System.Windows.Forms.Form
$main_form.Text ='Local Hyper-V LAB Setup'
$main_form.Width = 600
$main_form.Height = 800
$main_form.AutoSize = $true

$Label = New-Object System.Windows.Forms.Label
$Label.Text = "Select your LAB Type"
$Label.Location  = New-Object System.Drawing.Point(10,12)
$Label.AutoSize = $true
$main_form.Controls.Add($Label)

$ComboBox = New-Object System.Windows.Forms.ComboBox
$ComboBox.Width = 300
$Users = get-aduser -filter * -Properties SamAccountName
Foreach ($User in $Users)
{
$ComboBox.Items.Add($User.SamAccountName);
}
$ComboBox.Location  = New-Object System.Drawing.Point(130,10)
$main_form.Controls.Add($ComboBox)

$main_form.ShowDialog()
#>

# Variablecleanup
$VMPrefix = ""
$VMSwitchName = ""
$VMPath = ""
$ISOPath = ""
$ISO = ""
$sfbiso = ""
$exiso = ""
$ex13iso = ""
$ex16iso = ""
$ex19iso = ""
$sqliso = ""
$oosiso = ""
$ParentPath = ""
$VMList = ""
$VM = ""
$LAB_selector  = ""

# Variables
# VM location
$VMPath = "E:\Hyper-V"
# ISO location
$ISOPath = "F:\iso\VS(MSDN)"
# ISO Files
$ISO = "Windows Server\de-de_windows_server_2019_updated_aug_2021_x64_dvd_a11b80c3.iso" #Windows Server 2019
$sfbiso = "Skype for Business\de_skype_for_business_server_2015_x64_dvd_6622057.iso" #Skype for Business 2015
$ex13iso = "Exchange\mu_exchange_server_2013_with_sp1_x64_dvd_4059293.iso" #Exchange Server 2013
$ex16iso = "Exchange\mul_exchange_server_2016_cumulative_update_23_x64_dvd_a7c5e6ee.iso" #Exchange Server 2016
$ex19iso = "Exchange\mul_exchange_server_2019_cumulative_update_12_x64_dvd_52bf3153.iso" #Exchange Server 2019
$sqliso = "SQL\de_sql_server_2016_enterprise_with_service_pack_2_x64_dvd_12119061.iso" #SQL Server 2016
$oosiso = "de_office_online_server_last_updated_november_2018_x64_dvd_e1b74239.iso" #Office Online Server
#VHDX Parent path (Windows Server 2019)
$ParentPath = "D:\Hyper-V\base\WS_2019_18.09.22.vhdx" #Windows Server 2019 Base Image (Updated: September, 18, 2022)

#LAB list
$LAB_selector  = "new-sfb2015lab", "new-sfb2019lab", "new-ex2016lab", "new-ex2019lab", "new-ex2013lab"

function new-sfb2015lab {
### Skype for Business 2015 (3*FE+SQL) + Exchange + Office Web App Server

#Variables to differentiate LABS
$VMPrefix = "sfb15"
$VMSwitchName = "x-$VMPrefix"

# commented because of my VM Networking Setup
#Remove-VMSwitch -Name $VMSwitchName -Force
#New-VMSwitch -Name $VMSwitchName -SwitchType Private -Notes "Switch for Skype for Business 2015 Lab named: $VMSwitchName" 

$VMList = "$VMPrefix-LAB-DC",`
"$VMPrefix-LAB-$VMPrefix-1",`
"$VMPrefix-LAB-$VMPrefix-2",`
"$VMPrefix-LAB-$VMPrefix-3",`
"$VMPrefix-LAB-SQL",`
"$VMPrefix-LAB-Exchange",`
"$VMPrefix-LAB-oos",`
"$VMPrefix-LAB-Client"

ForEach ($VM in $VMList) {
New-VHD -Path "$VMPath\$VM\$VM.vhdx" `
-Differencing `
-ParentPath $ParentPath
New-VM -Name $VM `
-Generation 2 `
-MemoryStartupBytes 2GB `
-VHDPath "$VMPath\$VM\$VM.vhdx" `
-SwitchName $VMSwitchName `
-GuestStateIsolationType 'TrustedLaunch'
Set-VM -Name $VM `
-ProcessorCount 2 `
-DynamicMemory `
-MemoryMaximumBytes 16GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `
-Path "$ISOPath\$ISO"
Set-VMFirmware -VMName $VM -EnableSecureBoot On `
-FirstBootDevice ((Get-VMFirmware -VMName $VM).BootOrder | 
Where-Object Device -like *DvD*).Device
}

# SQL
Set-VM -Name "$VMPrefix-LAB-SQL" `
-ProcessorCount 4 `
-DynamicMemory `
-MemoryMaximumBytes 32GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-SQL" `
-Path "$ISOPath\$SQLISO"
# Exchange
Set-VM -Name "$VMPrefix-LAB-Exchange" `
-ProcessorCount 4 `
-DynamicMemory `
-MemoryMaximumBytes 32GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-Exchange" `
-Path "$ISOPath\$EXISO"
# Skype For Business
$VMList = "$VMPrefix-LAB-$VMPrefix-1",`
"$VMPrefix-LAB-$VMPrefix-2",`
"$VMPrefix-LAB-$VMPrefix-3"
ForEach ($VM in $VMList) {
Set-VM -Name $VM `
-ProcessorCount 2 `
-DynamicMemory `
-MemoryMaximumBytes 24GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `
-Path "$ISOPath\$sfbISO"
}
# Office Online Server
Set-VM -Name "$VMPrefix-LAB-oos" `
-ProcessorCount 2 `
-DynamicMemory `
-MemoryMaximumBytes 16GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-oos" `
-Path "$ISOPath\$OOSISO"

# Variablecleanup
$VMPrefix = ""
$VMSwitchName = ""
$VMPath = ""
$ISOPath = ""
$ISO = ""
$sfbiso = ""
$exiso = ""
$ex13iso = ""
$ex16iso = ""
$ex19iso = ""
$sqliso = ""
$oosiso = ""
$ParentPath = ""
$VMList = ""
$VM = ""
}

function new-sfb2019lab {
### Skype for Business 2019 (3*FE+SQL) + Exchange + Office Online Server

$VMPrefix = "sfb19"
$VMSwitchName = "x-$VMPrefix"

# commented because of my VM Networking Setup
#Remove-VMSwitch -Name $VMSwitchName -Force
#New-VMSwitch -Name $VMSwitchName -SwitchType Private -Notes "Switch for Skype for Business 2019 Lab named: $VMSwitchName" 

$VMList = "$VMPrefix-LAB-DC",`
"$VMPrefix-LAB-$VMPrefix-1",`
"$VMPrefix-LAB-$VMPrefix-2",`
"$VMPrefix-LAB-$VMPrefix-3",`
"$VMPrefix-LAB-SQL",`
"$VMPrefix-LAB-Exchange",`
"$VMPrefix-LAB-oos",`
"$VMPrefix-LAB-Client"

ForEach ($VM in $VMList) {
New-VHD -Path "$VMPath\$VM\$VM.vhdx" `
-Differencing `
-ParentPath $ParentPath
New-VM -Name $VM `
-Generation 2 `
-MemoryStartupBytes 2GB `
-VHDPath "$VMPath\$VM\$VM.vhdx" `
-SwitchName $VMSwitchName `
-GuestStateIsolationType 'TrustedLaunch'
Set-VM -Name $VM `
-ProcessorCount 2 `
-DynamicMemory `
-MemoryMaximumBytes 16GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `
-Path "$ISOPath\$ISO"
Set-VMFirmware -VMName $VM -EnableSecureBoot On `
-FirstBootDevice ((Get-VMFirmware -VMName $VM).BootOrder | 
Where-Object Device -like *DvD*).Device
}

# SQL
Set-VM -Name "$VMPrefix-LAB-SQL" `
-ProcessorCount 4 `
-DynamicMemory `
-MemoryMaximumBytes 32GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-SQL" `
-Path "$ISOPath\$SQLISO"
# Exchange
Set-VM -Name "$VMPrefix-LAB-Exchange" `
-ProcessorCount 4 `
-DynamicMemory `
-MemoryMaximumBytes 32GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-Exchange" `
-Path "$ISOPath\$EXISO"
# Skype For Business
$VMList = "$VMPrefix-LAB-$VMPrefix-1",`
"$VMPrefix-LAB-$VMPrefix-2",`
"$VMPrefix-LAB-$VMPrefix-3"
ForEach ($VM in $VMList) {
Set-VM -Name $VM `
-ProcessorCount 2 `
-DynamicMemory `
-MemoryMaximumBytes 24GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `
-Path "$ISOPath\$sfbISO"
}
# Office Online Server
Set-VM -Name "$VMPrefix-LAB-oos" `
-ProcessorCount 2 `
-DynamicMemory `
-MemoryMaximumBytes 16GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-oos" `
-Path "$ISOPath\$OOSISO"

# Variablecleanup
$VMPrefix = ""
$VMSwitchName = ""
$VMPath = ""
$ISOPath = ""
$ISO = ""
$sfbiso = ""
$exiso = ""
$ex13iso = ""
$ex16iso = ""
$ex19iso = ""
$sqliso = ""
$oosiso = ""
$ParentPath = ""
$VMList = ""
$VM = ""
}

function new-ex2016lab {
### Exchange 2016 3*FE + Office Web App Server

#Variables to differentiate different LABS
$VMPrefix = "ex16"
$VMSwitchName = "x-$VMPrefix"

# commented because of my VM Networking Setup
#Remove-VMSwitch -Name $VMSwitchName -Force
#New-VMSwitch -Name $VMSwitchName -SwitchType Private -Notes "Switch for Exchange 2016 Lab named: $VMSwitchName" 

$VMList = "$VMPrefix-LAB-DC",`
"$VMPrefix-LAB-$VMPrefix-1",`
"$VMPrefix-LAB-$VMPrefix-2",`
"$VMPrefix-LAB-$VMPrefix-3",`
"$VMPrefix-LAB-oos",`
"$VMPrefix-LAB-Client"

ForEach ($VM in $VMList) {
New-VHD -Path "$VMPath\$VM\$VM.vhdx" `
-Differencing `
-ParentPath $ParentPath
New-VM -Name $VM `
-Generation 2 `
-MemoryStartupBytes 2GB `
-VHDPath "$VMPath\$VM\$VM.vhdx" `
-SwitchName $VMSwitchName `
-GuestStateIsolationType 'TrustedLaunch'
Set-VM -Name $VM `
-ProcessorCount 2 `
-DynamicMemory `
-MemoryMaximumBytes 16GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `
-Path "$ISOPath\$ISO"
Set-VMFirmware -VMName $VM -EnableSecureBoot On `
-FirstBootDevice ((Get-VMFirmware -VMName $VM).BootOrder | 
Where-Object Device -like *DvD*).Device
}

# Exchange
$VMList = "$VMPrefix-LAB-$VMPrefix-1",`
"$VMPrefix-LAB-$VMPrefix-2",`
"$VMPrefix-LAB-$VMPrefix-3"
ForEach ($VM in $VMList) {
Set-VM -Name $VM `
-ProcessorCount 4 `
-DynamicMemory `
-MemoryMaximumBytes 24GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `
-Path "$ISOPath\$ex16iso"
}
# Office Online Server
Set-VM -Name "$VMPrefix-LAB-oos" `
-ProcessorCount 4 `
-DynamicMemory `
-MemoryMaximumBytes 16GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-oos" `
-Path "$ISOPath\$OOSISO"

# Variablecleanup
$VMPrefix = ""
$VMSwitchName = ""
$VMPath = ""
$ISOPath = ""
$ISO = ""
$sfbiso = ""
$exiso = ""
$ex13iso = ""
$ex16iso = ""
$ex19iso = ""
$sqliso = ""
$oosiso = ""
$ParentPath = ""
$VMList = ""
$VM = ""
}

function new-ex2019lab {
### Exchange 2019 3*FE + Office Web App Server

#Variables to differentiate different LABS
$VMPrefix = "ex19"
$VMSwitchName = "x-$VMPrefix"

# commented because of my VM Networking Setup
#Remove-VMSwitch -Name $VMSwitchName -Force
#New-VMSwitch -Name $VMSwitchName -SwitchType Private -Notes "Switch for Exchange 2019 Lab named: $VMSwitchName" 

$VMList = "$VMPrefix-LAB-DC",`
"$VMPrefix-LAB-$VMPrefix-1",`
"$VMPrefix-LAB-$VMPrefix-2",`
"$VMPrefix-LAB-$VMPrefix-3",`
"$VMPrefix-LAB-oos",`
"$VMPrefix-LAB-Client"

ForEach ($VM in $VMList) {
New-VHD -Path "$VMPath\$VM\$VM.vhdx" `
-Differencing `
-ParentPath $ParentPath
New-VM -Name $VM `
-Generation 2 `
-MemoryStartupBytes 2GB `
-VHDPath "$VMPath\$VM\$VM.vhdx" `
-SwitchName $VMSwitchName `
-GuestStateIsolationType 'TrustedLaunch'
Set-VM -Name $VM `
-ProcessorCount 2 `
-DynamicMemory `
-MemoryMaximumBytes 16GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `
-Path "$ISOPath\$ISO"
Set-VMFirmware -VMName $VM -EnableSecureBoot On `
-FirstBootDevice ((Get-VMFirmware -VMName $VM).BootOrder | 
Where-Object Device -like *DvD*).Device
}

# Exchange
$VMList = "$VMPrefix-LAB-$VMPrefix-1",`
"$VMPrefix-LAB-$VMPrefix-2",`
"$VMPrefix-LAB-$VMPrefix-3"
ForEach ($VM in $VMList) {
Set-VM -Name $VM `
-ProcessorCount 4 `
-DynamicMemory `
-MemoryMaximumBytes 24GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `
-Path "$ISOPath\$ex19iso"
}
# Office Online Server
Set-VM -Name "$VMPrefix-LAB-oos" `
-ProcessorCount 4 `
-DynamicMemory `
-MemoryMaximumBytes 16GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-oos" `
-Path "$ISOPath\$OOSISO"

# Variablecleanup
$VMPrefix = ""
$VMSwitchName = ""
$VMPath = ""
$ISOPath = ""
$ISO = ""
$sfbiso = ""
$exiso = ""
$ex13iso = ""
$ex16iso = ""
$ex19iso = ""
$sqliso = ""
$oosiso = ""
$ParentPath = ""
$VMList = ""
$VM = ""
}

function new-ex2013lab {
### Exchange 2013 3*FE + Office Web App Server

#Variables to differentiate different LABS
$VMPrefix = "ex13"
$VMSwitchName = "x-$VMPrefix"

# commented because of my VM Networking Setup
#Remove-VMSwitch -Name $VMSwitchName -Force
#New-VMSwitch -Name $VMSwitchName -SwitchType Private -Notes "Switch for Exchange 2013 Lab named: $VMSwitchName" 

$VMList = "$VMPrefix-LAB-DC",`
"$VMPrefix-LAB-$VMPrefix-1",`
"$VMPrefix-LAB-$VMPrefix-2",`
"$VMPrefix-LAB-$VMPrefix-3",`
"$VMPrefix-LAB-oos",`
"$VMPrefix-LAB-Client"

ForEach ($VM in $VMList) {
New-VHD -Path "$VMPath\$VM\$VM.vhdx" `
-Differencing `
-ParentPath $ParentPath
New-VM -Name $VM `
-Generation 2 `
-MemoryStartupBytes 2GB `
-VHDPath "$VMPath\$VM\$VM.vhdx" `
-SwitchName $VMSwitchName `
-GuestStateIsolationType 'TrustedLaunch'
Set-VM -Name $VM `
-ProcessorCount 2 `
-DynamicMemory `
-MemoryMaximumBytes 16GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `
-Path "$ISOPath\$ISO"
Set-VMFirmware -VMName $VM -EnableSecureBoot On `
-FirstBootDevice ((Get-VMFirmware -VMName $VM).BootOrder | 
Where-Object Device -like *DvD*).Device
}

# Exchange
$VMList = "$VMPrefix-LAB-$VMPrefix-1",`
"$VMPrefix-LAB-$VMPrefix-2",`
"$VMPrefix-LAB-$VMPrefix-3"
ForEach ($VM in $VMList) {
Set-VM -Name $VM `
-ProcessorCount 4 `
-DynamicMemory `
-MemoryMaximumBytes 24GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName $VM `
-Path "$ISOPath\$ex13iso"
}
# Office Online Server
Set-VM -Name "$VMPrefix-LAB-oos" `
-ProcessorCount 4 `
-DynamicMemory `
-MemoryMaximumBytes 16GB `
-AutomaticStartAction Nothing `
-AutomaticStopAction ShutDown
Add-VMDvdDrive -VMName "$VMPrefix-LAB-oos" `
-Path "$ISOPath\$OOSISO"

# Variablecleanup
$VMPrefix = ""
$VMSwitchName = ""
$VMPath = ""
$ISOPath = ""
$ISO = ""
$sfbiso = ""
$exiso = ""
$ex13iso = ""
$ex16iso = ""
$ex19iso = ""
$sqliso = ""
$oosiso = ""
$ParentPath = ""
$VMList = ""
$VM = ""
}

# XAML location
$xamlFile = ".\wpf\WpfApp1\WpfApp1\MainWindow.xaml"

#create window
$inputXML = Get-Content $xamlFile -Raw
$inputXML = $inputXML -replace 'mc:Ignorable="d"', '' -replace "x:N", 'N' -replace '^<Win.*', '<Window'
[XML]$XAML = $inputXML

#Read XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
try {
    $window = [Windows.Markup.XamlReader]::Load( $reader )
} catch {
    Write-Warning $_.Exception
    throw
}

# Create variables based on form control names.
# Variable will be named as 'var_<control name>'

$xaml.SelectNodes("//*[@Name]") | ForEach-Object {
    #"trying item $($_.Name)"
    try {
        Set-Variable -Name "var_$($_.Name)" -Value $window.FindName($_.Name) -ErrorAction Stop
    } catch {
        throw
    }
}

Foreach ($LAB in $LAB_selector) {
    $var_LAB_selector.Items.Add($LAB);
}

Get-Variable var_*

$Null = $window.ShowDialog()

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