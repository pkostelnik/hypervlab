# LAB on local Hyper-V
based on Windows 11 (should also work on Windows 10)

## Basic preparation
You need a "powerful" machine as Hyper-V Host:

* CPU: Intel I5/7/9 or AMD Ryzen 5/7/9
* Memory (RAM) 32 GB ++
* SSD around 512 GB ++

If you are choosing/building a new one, do not spend too much on CPU, Memory is way the better way for better performance with more then 4 VM's.

Next you need to have Windows 11/11 Pro++ installed on it including the Hyper-V role.
Being able to install VM's you need also some ISO Files for each System you wanna include in your LAB:
some of them are available at: https://www.microsoft.com/en-us/evalcenter/
| System | trial available | Link | Notes
|--|:--:|:--:|--:|
| Windows Server 2019 | [x] |https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019|
| Windows Server 2022 |[x]|https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022|
| Windows 10 Enterprise |[x]|https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise|
| Windows 11 Enterprise |[x]|https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise|
| Microsoft SQL Server 2016 |[x]|https://www.microsoft.com/en-us/evalcenter/evaluate-sql-server-2016|
| Microsoft SQL Server 2019 |[x]|https://www.microsoft.com/en-us/evalcenter/evaluate-sql-server-2019|
| Microsoft SQL Server 2022 |[x]|https://www.microsoft.com/en-us/evalcenter/evaluate-sql-server-2022|
| Skype for Business Server 2019 |[x]|https://www.microsoft.com/en-us/evalcenter/evaluate-skype-business-server-2019|
| SharePoint Server 2019 |[x]|https://www.microsoft.com/en-us/evalcenter/evaluate-sharepoint-server-2019|
| Microsoft Exchange Server 2019 | [] |https://learn.microsoft.com/en-us/exchange/new-features/build-numbers-and-release-dates?view=exchserver-2019&WT.mc_id=M365-MVP-5003086#exchange-server-2019| as there is no ISO for Exchange Server it's best to download it directly into you designated VM (use the latest CU) 
| Office Online Server | [] ||Office Online Server can be downloaded from the Volume Licensing Service Center (VLSC:https://go.microsoft.com/fwlink/p/?LinkId=256561). Office Online Server is a component of Office; therefore, it will be shown under each of the Office product pages including Office Standard 2016, Office Professional Plus 2016, and Office 2016 for Mac Standard.

the other way is to download the products from your visualstudio subscription: https://my.visualstudio.com/Downloads/Featured as long you own one.

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


The Preparation script is easy to enhance for more then the predefined number of VM's. In the same way you can also add your ISO Files for the staging.
