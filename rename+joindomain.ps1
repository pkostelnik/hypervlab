$Domain = "ent16.lab"
$User = "Administrator"
$NewName = "sp"
$DC = "DC"

Add-Computer -DomainName $Domain -Server "$DC.$Domain" -ComputerName "$env:COMPUTERNAME" -Credential "$Domain\$User" -newname $NewName -Restart