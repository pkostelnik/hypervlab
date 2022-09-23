# LAB on Hyper-V
## based on Windows 11 (should also word on Windows 10)

Here you will find some usefull PowerShell scripts, which will make a LAB deployement on Hyper-V (local) faster and hopefully also easier.

### Scripts included until 23.09.2022
* VM Prepopulation
* Install and Setup AD
* rename and domainjoin VM
* install all prerequisites for office online server

## Variables used in the scripts (which should be selfexplaining 😎)

| Variable | meaning |
|--|--:
|$VMPrefix = ""| used to set mark (VMname, Network and so on) in case of more then one lab |
|$VMSwitchName = ""| building the new virtual switch name |
|$VMPath = ""| where to save the whole VM data|
|$ISOPath = ""| Where is your path to the ISO files|
|$ISO = ""| Windows iSO name|
|$sfbiso = ""| Skype for Business Server iSO name|
|$exiso = ""| Exchange Server iSO name|
|$sqliso = ""|SQL Server iSO name |
|$oosiso = ""|Office Online Server iSO name |
|$ParentPath = ""|where to find your prepared Windows Server vhdx file |
|$VMList = ""| all of your VM machines list|
|$VM = ""| temporary variable for vm creation|
