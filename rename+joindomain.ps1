$Domain = "ent22.lab"
$User = "Administrator"
$NewName = "ex2"
$DC = "DC"

Add-Computer -DomainName $Domain -Server "$DC.$Domain" -ComputerName "$env:COMPUTERNAME" -Credential "$Domain\$User" -newname $NewName -Restart