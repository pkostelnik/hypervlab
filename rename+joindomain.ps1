$Domain = "rmt22.lab"
$User = "Administrator"
$NewName = "rdh1"
$DC = "DC"

Add-Computer -DomainName $Domain -Server "$DC.$Domain" -ComputerName "$env:COMPUTERNAME" -Credential "$Domain\$User" -newname $NewName -Restart