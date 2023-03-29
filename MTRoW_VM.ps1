<#
.SYNOPSIS

    Create SRSv2 media appropriate for setting up an SRSv2 device.


.DESCRIPTION

    This script automates some sanity checks and copying operations that are
    necessary to create bootable SRSv2 media. Booting an SRSv2 device using the
    media created from this process will result in the SRSv2 shutting down. The
    SRSv2 can then either be put into service, or booted with separate WinPE
    media for image capture.

    To use this script, you will need:

    1. An Internet connection
    2. A USB drive with sufficient space (16GB+), inserted into this computer
    3. Windows 10 Enterprise or Windows 10 Enterprise IoT media, which must be
       accessible from this computer (you will be prompted for a path). The
       Windows media build number must match the build required by the SRSv2
       deployment kit.

.EXAMPLE
    .\CreateSrsMedia

    Prompt for required information, validate provided inputs, and (if all
    validations pass) create media on the specified USB device.

.NOTES

    This script requires that you provide Windows media targeted for the x64
    architecture.

    Only one driver pack can be used at a time. Each unique supported SKU of
    SRSv2 computer hardware must have its own, separate image.

    The build number of the Windows media being used *must* match the build
    required by the SRSv2 deployment kit.

#>

<#
Revision history
    1.0.0  - Initial release
    1.0.1  - Support source media with WIM >4GB
    1.1.0  - Switch Out-Null to Write-Debug for troubleshooting
             Record transcripts for troubleshooting
             Require the script be run from a path without spaces
             Require the script be run from an NTFS filesystem
             Soft check for sufficient scratch space
             Warn that the target USB drive will be wiped
             Rethrow exceptions after cleanup on main path
    1.2.0  - Indicate where to get Enterprise media
             Improve error handling for non-Enterprise media
             Report and exit on copy errors
             Work with spaces in the script's path
             Explicitly reject Windows 10 Media Creation Tool media
             Fix OEM media regression caused by splitting WIMs
    1.3.1  - Read config information from MSI
             Added infrastructure for downloading files
             Support for automatically downloading Windows updates
             Support for automatically downloading the deployment kit MSI
             Support for self-updating
             Added menu-driven driver selection/downloading
    1.3.2  - Fix OEM media regression caused by splitting WIMs
    1.4.0  - Support BIOS booting
    1.4.1  - BIOS booting controlled by metadata
    1.4.2  - Fix driver pack informative output
             Add 64-bit check to prevent 32-bit accidents
             Add debugging cross-check
             Add checks to prevent the script being run in weird ways
             Add warning about image cleanup taking a long time
             Fix space handling in self-update
    1.4.3  - Add non-terminating disk initialization logic
             Delete "system volume information" to prevent Windows Setup issues
             Add return code checking for native commands
    1.4.4  - Improve rejection of non-LP CABs
    1.4.5  - Add host OS check to prevent older DISM etc. mangling newer images
    1.5.0  - Add support for mismatched OS build number vs. feature build number
    1.5.1  - Change OEM default key.
    1.6.0  - Add support for mismatched OS build number vs. language build number
    1.6.1  - Use default credentials with the default proxy
    1.7.0  - Add metadata for clearer "human readable" Windows version information
             Change required input from Windows install media path to Windows ISO path
             Add size and hash check for input Windows ISO
    1.7.1  - Remove ePKEA references
             Improve ISO path input handling to allow quoted paths
             Fix directory left behind when script runs successfully
             Improve diagnostic output so it's less obtrusive
    1.8.0  - Add support for deployment kits that require Windows 11
             Improve ISO requirements messaging, so it's always stated
             Change names, add comments to reduce cases of mistaken code divers

#>
[CmdletBinding()]
param(
    [Switch]$ShowVersion, <# If set, output the script version number and exit. #>
    [Switch]$Manufacturing <# Internal use. #>
)

$ErrorActionPreference = "Stop"
$DebugPreference = if($PSCmdlet.MyInvocation.BoundParameters["Debug"]) { "Continue" } else { "SilentlyContinue" }
Set-StrictMode -Version Latest

$CreateSrsMediaScriptVersion = "1.8.0"

$SrsKitHumanVersion = $null
$SrsKitVlscName = $null
$SrsKitIsoSize = $null
$SrsKitIsoSha256 = $null


$robocopy_success = {$_ -lt 8 -and $_ -ge 0}

if ($ShowVersion) {
    Write-Output $CreateSrsMediaScriptVersion
    exit
}

function Remove-Directory {
  <#
    .SYNOPSIS
        
        Recursively remove a directory and all its children.

    .DESCRIPTION

        Powershell can't handle 260+ character paths, but robocopy can. This
        function allows us to safely remove a directory, even if the files
        inside exceed Powershell's usual 260 character limit.
  #>
param(
    [parameter(Mandatory=$true)]
    [string]$path <# The path to recursively remove #>
)

    # Make an empty reference directory
    $cleanup = Join-Path $PSScriptRoot "empty-temp"
    if (Test-Path $cleanup) {
        Remove-Item -Path $cleanup -Recurse -Force
    }
    New-Item -ItemType Directory $cleanup | Write-Debug

    # Use robocopy to clear out the guts of the victim path
    (Invoke-Native "& robocopy '$cleanup' '$path' /mir" $robocopy_success) | Write-Debug

    # Remove the folders, now that they're empty.
    Remove-Item $path -Force
    Remove-Item $cleanup -Force
}

function Test-OsIsoPath {
  <#
    .SYNOPSIS

        Test if $OsIsoPath is the expected Windows setup ISO for SRSv2.

    .DESCRIPTION

        Tests if the provided path references the Windows setup ISO
        that matches the media indicated in the SRSv2 installation
        metadata. Specifically, the ISO must:

          - Be the correct size
          - Produce the correct SHA256 hash

    .OUTPUTS bool

        $true if $OsIsoPath refers to the expected ISO, $false otherwise.
  #>
param(
  [parameter(Mandatory=$true)]
  $OsIsoPath, <# Path to the ISO file to check #>
  [parameter(Mandatory=$true)]
  $KitIsoSize, <# Expected size of the ISO in bytes #>
  [parameter(Mandatory=$true)]
  $KitIsoSha256, <# Expected SHA256 hash of the ISO file #>
  [parameter(Mandatory=$true)]
  [switch]$IsOem <# Whether OEM media is being used #>
)

    if (!(Test-Path $OsIsoPath)) {
        Write-Host "The path provided does not exist. Please specify a path to a Windows installation ISO file."
        return $false
    }

    if (!(Test-Path $OsIsoPath -PathType Leaf)) {
        Write-Host "The path provided does not refer to a file. Please specify a path to a Windows installation ISO file."
        return $false
    }

    $Iso = Get-ChildItem $OsIsoPath

    if ($Iso.Length -ne $KitIsoSize) {
        Write-Host "The ISO does not match the expected size."
        Write-Host "Verify that you downloaded the correct file, and that it is not corrupted."
        PrintWhereToGetMedia -IsOem:$IsOem
        return $false
    }

    if ((Get-FileHash -Algorithm SHA256 $Iso).Hash -ne $KitIsoSha256) {
        Write-Host "The ISO does not match the expected SHA256 hash."
        Write-Host "Verify that you downloaded the correct file, and that it is not corrupted."
        PrintWhereToGetMedia -IsOem:$IsOem
        return $false
    }

    return $true
}

function Test-Unattend-Compat {
    <#
        .SYNOPSIS
        
            Test to see if this script is compatible with a given SRSv2 Unattend.xml file.

        .DESCRIPTION

            Looks for metadata in the $xml parameter indicating the lowest version of
            the CreateSrsMedia script the XML file will work with.

        .OUTPUTS bool
            
            Return $true if CreateSrsMedia is compatible with the SRSv2
            Unattend.xml file in $xml, $false otherwise.
    #>
param(
    [parameter(Mandatory=$true)]
    [System.Xml.XmlDocument]$Xml, <# The SRSv2 AutoUnattend to check compatibility with. #>
    [parameter(Mandatory=$true)]
    [int]$Rev <# The maximum compatibility revision this script supports. #>
)
    $nodes = $Xml.SelectNodes("//comment()[starts-with(normalize-space(translate(., 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')), 'srsv2-compat-rev:')]")

    # If the file has no srsv2-compat-rev value, assume rev 0, which all scripts work with.
    if ($nodes -eq $null -or $nodes.Count -eq 0) {
        return $true
    }

    $URev = 0

    # If there is more than one value, be conservative: take the biggest value
    $nodes | 
    ForEach-Object {
        $current = $_.InnerText.Split(":")[1]
        if ($URev -lt $current) {
            $URev = $current
        }
    }

    return $Rev -ge $URev

}

function Remove-Xml-Comments {
  <#
    .SYNOPSIS
        
        Remove all comments that are direct children of $node.

    .DESCRIPTION
        
        Remove all the comment children nodes (non-recursively) from the specified $node.
  #>
param(
    [parameter(Mandatory=$true)]
    [System.Xml.XmlNode]$node <# The XML node to strip comments from. #>
)
    $node.SelectNodes("comment()") |
    ForEach-Object {
        $node.RemoveChild($_) | Write-Debug
    }
}

function Add-AutoUnattend-Key {
  <#
    .SYNOPSIS
        
        Inject $key as a product key into the AutoUnattend XML $xml.

    .DESCRIPTION
        
        Injects the $key value as a product key in $xml, where $xml is an
        AutoUnattend file already containing a Microsoft-Windows-Setup UserData
        node. Any comments in the UserData node are stripped.

        If a ProductKey node already exists, this function does *not* remove or
        replace it.
  #>
param(
    [parameter(Mandatory=$true)]
    [System.Xml.XmlDocument]$xml, <# The SRSv2 AutoUnattend to modify. #>
    [parameter(Mandatory=$true)]
    [string]$key <# The Windows license key to inject. #>
)

    $XmlNs = @{"u"="urn:schemas-microsoft-com:unattend"}
    $node = (Select-Xml -Namespace $XmlNs -Xml $xml -XPath "//u:settings[@pass='specialize']").Node
    $NShellSetup = $xml.CreateElement("", "component", $XmlNs["u"])
    $NShellSetup.SetAttribute("name", "Microsoft-Windows-Shell-Setup") | Write-Debug
    $NShellSetup.SetAttribute("processorArchitecture", "amd64") | Write-Debug
    $NShellSetup.SetAttribute("publicKeyToken", "31bf3856ad364e35") | Write-Debug
    $NShellSetup.SetAttribute("language", "neutral") | Write-Debug
    $NShellSetup.SetAttribute("versionScope", "nonSxS") | Write-Debug
    $NProductKey = $xml.CreateElement("", "ProductKey", $XmlNs["u"])
    $NProductKey.InnerText = $key
    $NShellSetup.AppendChild($NProductKey) | Write-Debug
    $node.PrependChild($NShellSetup) | Write-Debug
}

function Set-AutoUnattend-Partitions {
  <#
    .SYNOPSIS

        Set up the AutoUnattend file for use with BIOS based systems, if requested.

    .DESCRIPTION

        If -BIOS is specified, reconfigure a (nominally UEFI) AutoUnattend
        partition configuration to be compatible with BIOS-based systems
        instead. Otherwise, do nothing.
  #>
param(
    [parameter(Mandatory=$true)]
    [System.Xml.XmlDocument]$xml, <# The SRSv2 AutoUnattend to modify. #>
    [parameter(Mandatory=$true)]
    [switch]$BIOS <# If True, assume UEFI input and reconfigure for BIOS. #>
)

    # for UEFI, do nothing.
    if (!$BIOS) {
        return
    }

    # BIOS logic...
    $XmlNs = @{"u"="urn:schemas-microsoft-com:unattend"}
    $node = (Select-Xml -Namespace $XmlNs -Xml $xml -XPath "//u:settings[@pass='windowsPE']/u:component[@name='Microsoft-Windows-Setup']").Node

    # Remove the first partition (EFI)
    $node.DiskConfiguration.Disk.CreatePartitions.RemoveChild($node.DiskConfiguration.Disk.CreatePartitions.CreatePartition[0]) | Write-Debug

    # Re-number the remaining partition as 1
    $node.DiskConfiguration.Disk.CreatePartitions.CreatePartition.Order = "1"

    # Install to partition 1
    $node.ImageInstall.OSImage.InstallTo.PartitionID = "1"
}

function Set-AutoUnattend-Sysprep-Mode {
  <#
    .SYNOPSIS
        
        Set the SRSv2 sysprep mode to "reboot" or "shutdown" in the AutoUnattend file $xml.

    .DESCRIPTION
        
        Sets the SRSv2 AutoUnattend represented by $xml to either reboot (if
        -Reboot is used), or shut down (if -shutdown is used). Any comments
        under the containing RunSynchronousCommand node are stripped.

        This function assumes that a singular sysprep command is specified in
        $xml with /generalize and /oobe flags, in the auditUser pass,
        Microsoft-Windows-Deployment component. It further assumes that the
        sysprep command has the /reboot option specified by default.
  #>
param(
    [parameter(Mandatory=$true)]
    [System.Xml.XmlDocument]$Xml, <# The SRSv2 AutoUnattend to modify. #>
    [parameter(Mandatory=$true,ParameterSetName='reboot')]
    [switch]$Reboot, <# Whether sysprep should perform a reboot or a shutdown. #>
    [parameter(Mandatory=$true,ParameterSetName='shutdown')]
    [switch]$Shutdown <# Whether sysprep should perform a shutdown or a reboot. #>
)
    $XmlNs = @{"u"="urn:schemas-microsoft-com:unattend"}
    $node = (Select-Xml -Namespace $XmlNs -Xml $Xml -XPath "//u:settings[@pass='auditUser']/u:component[@name='Microsoft-Windows-Deployment']/u:RunSynchronous/u:RunSynchronousCommand/u:Path[contains(translate(text(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'sysprep') and contains(translate(text(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'generalize') and contains(translate(text(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'oobe')]").Node
    Remove-Xml-Comments $node.ParentNode
    if ($Shutdown -or !$Reboot) {
        $node.InnerText = $node.InnerText.ToLowerInvariant() -replace ("/reboot", "/shutdown")
    }
}

function Get-TextListSelection {
  <#
    .SYNOPSIS

        Prompt the user to pick an item from an array.


    .DESCRIPTION

        Given an array of items, presents the user with a text-based, numbered
        list of the array items. The user must then select one item from the
        array (by index). That index is then returned.

        Invalid selections cause the user to be re-prompted for input.


    .OUTPUTS int

        The index of the item the user selected from the array.
  #>
  param(
    [parameter(Mandatory=$true)]<# The list of objects to select from #>
    $Options,
    [parameter(Mandatory=$false)]<# The property of the objects to use for the list #>
    $Property = $null,
    [parameter(Mandatory=$false)]<# The prompt to display to the user #>
    $Prompt = "Selection",
    [parameter(Mandatory=$false)]<# Whether to allow a blank entry to make the default selection #>
    [switch]
    $AllowDefault = $true,
    [parameter(Mandatory=$false)]<# Whether to automatically select the default value, without prompting #>
    [switch]
    $AutoDefault = $false
  )

  $index = 0
  $response = -1
  $DefaultValue = $null
  $DefaultIndex = -1

  if ($AllowDefault) {
    $DefaultIndex = 0
    if ($AutoDefault) {
      return $DefaultIndex
    }
  }

  $Options | Foreach-Object -Process {
    $value = $_
    if ($Property -ne $null) {
      $value = $_.$Property
    }
    if ($DefaultValue -eq $null) {
      $DefaultValue = $value
    }
    Write-Host("[{0,2}] {1}" -f $index, $value)
    $index++
  } -End {
    if ($AllowDefault) {
      Write-Host("(Default: {0})" -f $DefaultValue)
    }
    while ($response -lt 0 -or $response -ge $Options.Count) {
      try {
        $response = Read-Host -Prompt $Prompt -ErrorAction SilentlyContinue
        if ([string]::IsNullOrEmpty($response)) {
          [int]$response = $DefaultIndex
        } else {
          [int]$response = $response
        }
      } catch {}
    }
  }

  # Write this out for transcript purposes.
  Write-Transcript ("Selected option {0}." -f $response)

  return $response
}

function SyncDirectory {
  <#
    .SYNOPSIS
        Sync a source directory to a destination.

    .DESCRIPTION
        Given a source and destination directories, make the destination
        directory's contents match the source's, recursively.
  #>
  param(
    [parameter(Mandatory=$true)] <# The source directory containing the subirectory to sync. #>
    $Src,
    [parameter(Mandatory=$true)] <# The destination directory that may or may not yet contain the subdirectory being synchronized #>
    $Dst,
    [parameter(Mandatory=$false)] <# Any additional flags to pass to robocopy #>
    $Flags
  )

  (Invoke-Native "& robocopy /mir '$Src' '$Dst' /R:0 $Flags" $robocopy_success) | Write-Debug
  if ($LASTEXITCODE -gt 7) {
    Write-Error ("Copy failed. Try re-running with -Debug to see more details.{0}Source: {1}{0}Destination: {2}{0}Flags: {3}{0}Error code: {4}" -f "`n`t", $Src, $Dst, ($Flags -Join " "), $LASTEXITCODE)
  }
}

function SyncSubdirectory {
  <#
    .SYNOPSIS
        Sync a single subdirectory from a source directory to a destination.

    .DESCRIPTION
        Given a source directory Src with a subdirectory Subdir, recreate Subdir
        as a subdirectory under Dst.
  #>
  param(
    [parameter(Mandatory=$true)] <# The source directory containing the subirectory to sync. #>
    $Src,
    [parameter(Mandatory=$true)] <# The destination directory that may or may not yet contain the subdirectory being synchronized #>
    $Dst,
    [parameter(Mandatory=$true)] <# The name of the subdirectory to synchronize #>
    $Subdir,
    [parameter(Mandatory=$false)] <# Any additional flags to pass to robocopy #>
    $Flags
  )

  $Paths = Join-Path -Path @($Src, $Dst) -ChildPath $Subdir
  SyncDirectory $Paths[0] $Paths[1] $Flags
}

function SyncSubdirectories {
  <#
    .SYNOPSIS
        Recreate each subdirectory from the source in the destination.

    .DESCRIPTION
        For each subdirectory contained in the source, synchronize with a
        corresponding subdirectory in the destination. This does not synchronize
        non-directory files from the source to the destination, nor does it
        purge "extra" subdirectories in the destination where the source does
        not contain such directories.
  #>
  param(
    [parameter(Mandatory=$true)] <# The source directory #>
    $Src,
    [parameter(Mandatory=$true)] <# The destination directory #>
    $Dst,
    [parameter(Mandatory=$false)] <# Any additional flags to pass to robocopy #>
    $Flags
  )

  Get-ChildItem $Src -Directory | ForEach-Object { SyncSubdirectory $Src $Dst $_.Name $Flags }
}

function ConvertFrom-PSCustomObject {
<#
    .SYNOPSIS
        Recursively convert a PSCustomObject to a hashtable.

    .DESCRIPTION
        Converts a set of (potentially nested) PSCustomObjects into an easier-to-
        manipulate set of (potentially nested) hashtables. This operation does not
        recurse into arrays; any PSCustomObjects embedded in arrays will be left
        as-is.

    .OUTPUT hashtable
#>
param(
    [parameter(Mandatory=$true)]
    [PSCustomObject]$object <# The PSCustomeObject to recursively convert to a hashtable #>
)

    $retval = @{}

    $object.PSObject.Properties |% {
        $value = $null

        if ($_.Value -ne $null -and $_.Value.GetType().Name -eq "PSCustomObject") {
            $value = ConvertFrom-PSCustomObject $_.Value
        } else {
            $value = $_.Value
        }
        $retval.Add($_.Name, $value)
    }
    return $retval
}

function Resolve-Url {
<#
    .SYNOPSIS
        Recursively follow URL redirections until a non-redirecting URL is reached.

    .DESCRIPTION
        Chase URL redirections (e.g., FWLinks, safe links, URL-shortener links)
        until a non-redirection URL is found, or the redirection chain is deemed
        to be too long.

    .OUTPUT System.Uri
#>
param(
    [Parameter(Mandatory=$true)]
    [String]$url <# The URL to (recursively) resolve to a concrete target. #>
)
    $orig = $url
    $result = $null
    $depth = 0
    $maxdepth = 10

    do {
        if ($depth -ge $maxdepth) {
            Write-Error "Unable to resolve $orig after $maxdepth redirects."
        }
        $depth++
        $resolve = [Net.WebRequest]::Create($url)
        $resolve.Method = "HEAD"
        $resolve.AllowAutoRedirect = $false
        $result = $resolve.GetResponse()
        $url = $result.GetResponseHeader("Location")
    } while ($result.StatusCode -eq "Redirect")

    if ($result.StatusCode -ne "OK") {
        Write-Error ("Unable to resolve {0} due to status code {1}" -f $orig, $result.StatusCode)
    }

    return $result.ResponseUri
}

function Save-Url {
<#
    .SYNOPSIS
        Given a URL, download the target file to the same path as the currently-
        running script.

    .DESCRIPTION
        Download a file referenced by a URL, with some added niceties:

          - Tell the user the file is being downloaded
          - Skip the download if the file already exists
          - Keep track of partial downloads, and don't count them as "already
            downloaded" if they're interrupted

        Optionally, an output file name can be specified, and it will be used. If
        none is specified, then the file name is determined from the (fully
        resolved) URL that was provided.

    .OUTPUT string
#>
param(
    [Parameter(Mandatory=$true)]
    [String]$url, <# URL to download #>
    [Parameter(Mandatory=$true)]
    [String]$name, <# A friendly name describing what (functionally) is being downloaded; for the user. #>
    [Parameter(Mandatory=$false)]
    [String]$output = $null <# An optional file name to download the file as. Just a file name -- not a path! #>
)

    $res = (Resolve-Url $url)

    # If the filename is not specified, use the filename in the URL.
    if ([string]::IsNullOrEmpty($output)) {
        $output = (Split-Path $res.LocalPath -Leaf)
    }

    $File = Join-Path $PSScriptRoot $output
    if (!(Test-Path $File)) {
        Write-Host "Downloading $name... " -NoNewline
        $TmpFile = "${File}.downloading"

        # Clean up any existing (unfinished, previous) download.
        Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue

        # Download to the temp file, then rename when the download is complete
        (New-Object System.Net.WebClient).DownloadFile($res, $TmpFile)
        Rename-Item $TmpFile $File -Force

        Write-Host "done"
    } else {
        Write-Host "Found $name already downloaded."
    }

    return $File
}

function Test-Signature {
<#
    .SYNOPSIS
        Verify the AuthentiCode signature of a file, deleting the file and writing
        an error if it fails verification.

    .DESCRIPTION
        Given a path, check that the target file has a valid AuthentiCode signature.
        If it does not, delete the file, and write an error to the error stream.
#>
param(
    [Parameter(Mandatory=$true)]
    [String]$Path <# The path of the file to verify the Authenticode signature of. #>
)
    if (!(Test-Path $Path)) {
        Write-Error ("File does not exist: {0}" -f $Path)
    }

    $name = (Get-Item $Path).Name
    Write-Host ("Validating signature for {0}... " -f $name) -NoNewline

    switch ((Get-AuthenticodeSignature $Path).Status) {
        ("Valid") {
            Write-Host "success."
        }

        default {
            Write-Host "failed."

            # Invalid files should not remain where they could do harm.
            Remove-Item $Path | Write-Debug
            Write-Error ("File {0} failed signature validation." -f $name)
        }
    }
}

function PrintWhereToGetLangpacks {
param(
    [parameter(Mandatory=$false)]
    [switch]$IsOem
)
    if ($IsOem) {
        Write-Host ("   OEMs:            http://go.microsoft.com/fwlink/?LinkId=131359")
        Write-Host ("   System builders: http://go.microsoft.com/fwlink/?LinkId=131358")
    } else {
        Write-Host ("   MPSA customers:         http://go.microsoft.com/fwlink/?LinkId=125893")
        Write-Host ("   Other volume licensees: http://www.microsoft.com/licensing/servicecenter")
    }
}

function PrintWhereToGetMedia {
param(
    [parameter(Mandatory=$false)]
    [switch]$IsOem
)

    if ($IsOem) {
        Write-Host ("   OEMs must order physical Windows 10 Enterprise IoT media.")
    } else {
        Write-Host ("   Enterprise customers can access Windows 10 Enterprise media from the Volume Licensing Service Center:")
        Write-Host ("   http://www.microsoft.com/licensing/servicecenter")
    }

    if ($script:SrsKitIsoSize -eq $null) {
        return
    }

    Write-Host     ("")
    Write-Host     ("   The correct media for this release has the following characteristics:")
    Write-Host     ("")
    Write-Host     ("     Major release: $script:SrsKitHumanVersion")
    if (!$IsOem) {
        Write-Host ("     Name in VLSC: $script:SrsKitVlscName")
    }
    Write-Host     ("     Size (bytes): $script:SrsKitIsoSize")
    Write-Host     ("     SHA256: $script:SrsKitIsoSha256")
    Write-Host     ("")
    Write-Host     ("   You must supply an ISO that matches the exact characteristics above.")
}

function Render-Menu {
<#
    .SYNOPSIS
      Present a data-driven menu system to the user.

    .DESCRIPTION
      Render a data-driven menu system to guide the user through more complicated
      decision-making processes.

    .NOTES
      Right now, the menu system is used only for selecting which driver pack to
      download.

      Action: Download
      Parameters:
        - Targets: an array of strings (URLs)
      Description:
        Chases redirects and downloads each URL listed in the "Targets" array.
        Verifies the downloaded file's AuthentiCode signature.
      Returns:
        a string (file path) for each downloaded file.

      Action: Menu
      Parameters:
        - Targets: an array of other MenuItem names (each must be a key in $MenuItems)
        - Message: Optional. The prompt text to use when asking for the user's
                   selection.
      Description:
        Presents a menu, composed of the names listed in "Targets," to the user. The
        menu item that is selected by the user is then recursively passed to
        Render-Menu for processing.

      Action: Redirect
      Parameters:
        - Target: A MenuItem name (must be a key in $MenuItems)
      Description:
        The menu item indicated by "Target" is recursively passed to Render-Menu
        for processing.

      Action: Warn
      Parameters:
        - Message: The warning to display to the user
      Description:
        Displays a warning consisting of the "Message" text to the user.

    .OUTPUT string
      One or more strings, each representing a downloaded file.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory=$true)]
    $MenuItem, <# The initial menu item to process #>
    [parameter(Mandatory=$true)]
    $MenuItems, <# The menu items (recursively) referenced by the initial menu item #>
    [parameter(Mandatory=$true)]
    [hashtable]$Variables
)
    if ($MenuItem.ContainsKey("Variables")) {
        foreach ($Key in $MenuItem["Variables"].Keys) {
            if ($Variables.ContainsKey($Key)) {
                $Variables[$Key] = $MenuItem["Variables"][$Key]
            } else {
                $Variables.Add($Key, $MenuItem["Variables"][$Key])
            }
        }
    }
    Switch ($MenuItem.Action) {
        "Download" {
            Write-Verbose "Processing download menu entry."
            ForEach ($URL in $MenuItem["Targets"]) {
                $file = (Save-Url $URL "driver")
                Test-Signature $file
                Write-Output $file
            }
        }

        "Menu" {
            Write-Verbose "Processing nested menu entry."
            $Options = $MenuItem["Targets"]
            $Prompt = @{}
            if ($MenuItem.ContainsKey("Message")) {
                $Prompt = @{ "Prompt"=($MenuItem["Message"]) }
            }
            $Selection = $MenuItem["Targets"][(Get-TextListSelection -Options $Options -AllowDefault:$false @Prompt)]
            Render-Menu -MenuItem $MenuItems[$Selection] -MenuItems $MenuItems -Variables $Variables
        }

        "Redirect" {
            Write-Verbose ("Redirecting to {0}" -f $MenuItem["Target"])
            Render-Menu -MenuItem $MenuItems[$MenuItem["Target"]] -MenuItems $MenuItems -Variables $Variables
        }

        "Warn" {
            Write-Warning $MenuItem["Message"]
        }
    }
}

function Invoke-Native {
<#
    .SYNOPSIS
        Run a native command and process its exit code.

    .DESCRIPTION
        Invoke a command line specified in $command, and check the resulting $LASTEXITCODE against
        $success to determine if the command succeeded or failed. If the command failed, error out.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory=$true)]
    [string]$command, <# The native command to execute. #>
    [parameter(Mandatory=$false)]
    [ScriptBlock]$success = {$_ -eq 0} <# Test of $_ (last exit code) that returns $true if $command was successful, $false otherwise. #>
)

    Invoke-Expression $command
    $result = $LASTEXITCODE
    if (!($result |% $success)) {
        Write-Error "Command '$command' failed test '$success' with code '$result'."
        exit 1
    }
}

function Expand-Archive {
<#
    .SYNOPSIS
        Extract files from supported archives.

    .NOTES
        Supported file types are .msi and .cab.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory=$true)]
    [string]$source, <# The archive file to expand. #>
    [parameter(Mandatory=$true)]
    [string]$destination <# The directory to place the extracted archive files in. #>
)

    if (!(Test-Path $destination)) {
        mkdir $destination | Write-Debug
    }

    switch ([IO.Path]::GetExtension($source)) {
        ".msi" {
            Start-Process "msiexec" -ArgumentList ('/a "{0}" /qn TARGETDIR="{1}"' -f $source, $destination) -NoNewWindow -Wait
        }
        ".cab" {
            (& expand.exe "$source" -F:* "$destination") | Write-Debug
        }
        default {
            Write-Error "Unsupported archive type."
            exit 1
        }
    }
}

function Write-Transcript {
<#
    .SYNOPSIS
        Write diagnostic strings to the transcript, while keeping them
        unobtrusive in the normal script output.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory=$true)]
    [string]$message
)

    Write-Host -ForegroundColor (Get-Host).UI.RawUI.BackgroundColor $message
}

####
## Start of main script
####

Start-Transcript

$WindowsIsoMount = $null

try {
    $AutoUnattendCompatLevel = 2

    # Set the default proxy to use default credentials.
    # .NET really should do this (and can, via System.Net DefaultProxy's "UseDefaultCredentials" flag), but
    # that flag is not set by default, and getting it set external to this script is unreasonably cumbersome.
    # Setting this value once, here, is sufficient for all further instances in this script to use the
    # default credentials.
    (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

    # Just creating a lower scope for the temp vars.
    $ActualRuntime = "0.0.0.0"
    if ($true) {
        # Build a complete version string for the current OS this script is running on.
        $a = [System.Environment]::OSVersion.Version
        $b = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name UBR).UBR
        $ActualRuntime = [version]::New($a.Major, $a.Minor, $a.Build, $b)
    }

    # Warn about versions of Windows the script may not be tested with.
    # This ONLY has to do with the machine this script is ACTIVELY RUNNING ON.
    [version]$ScriptMinimumTestedRuntime = [version]::New("10", "0", "19045", "2604")
    if ($ActualRuntime -lt $ScriptMinimumTestedRuntime) {
        Write-Warning "This version of Windows may not be new enough to run this script."
        Write-Warning "If you encounter problems, please update to the latest widely-available version of Windows."
    }

    Write-Host "This script is running on OS build $ActualRuntime"

    # We have to do the copy-paste check first, as an "exit" from a copy-paste context will
    # close the PowerShell instance (even PowerShell ISE), and prevent other exit-inducing
    # errors from being seen.
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Write-Host "This script must be saved to a file, and run as a script."
        Write-Host "It cannot be copy-pasted into a PowerShell prompt."

        # PowerShell ISE doesn't allow reading a key, so just wait a day...
        if (Test-Path Variable:psISE) {
            Start-Sleep -Seconds (60*60*24)
            exit
        }

        # Wait for the user to see the error and acknowledge before closing the shell.
        Write-Host -NoNewLine 'Press any key to continue...'
        $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') | Out-Null
        exit
    }

    # DISM commands don't work in 32-bit PowerShell.
    try {
        if (!([Environment]::Is64BitProcess)) {
            Write-Host "This script must be run from 64-bit PowerShell."
            exit
        }
    } catch {
        Write-Host "Please make sure you have the latest version of PowerShell and the .NET runtime installed."
        exit
    }

    # Dot-sourcing is unecessary for this script, and has weird behaviors/side-effects.
    # Don't permit it.
    if ($MyInvocation.InvocationName -eq ".") {
        Write-Host "This script does not support being 'dot sourced.'"
        Write-Host "Please call the script using only its full or relative path, without a preceding dot/period."
        exit
    }

    # Like dot-sourcing, PowerShell ISE executes stuff in a way that causes weird behaviors/side-effects,
    # and is generally a hassle (and unecessary) to support.
    if (Test-Path Variable:psISE) {
        Write-Host "This script does not support being run in Powershell ISE."
        Write-Host "Please call this script using the normal PowerShell prompt, or by passing the script name directly to the PowerShell.exe executable."
        exit
    }

    # Have to be admin to do things like DISM commands.
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "This script must be run from an elevated console."
        exit
    }

    Write-Host ("Script version {0}" -f $CreateSrsMediaScriptVersion)
    $UpdatedScript = Save-Url "https://go.microsoft.com/fwlink/?linkid=867842" "CreateSrsMedia" "update.ps1"
    Test-Signature $UpdatedScript
    Unblock-File $UpdatedScript
    [Version]$UpdatedScriptVersion = (& powershell -executionpolicy unrestricted ($UpdatedScript.Replace(" ", '` ')) -ShowVersion)
    if ($UpdatedScriptVersion -gt [Version]$CreateSrsMediaScriptVersion) {
        Write-Host ("Newer script found, version {0}" -f $UpdatedScriptVersion)
        Remove-Item $PSCommandPath
        Rename-Item $UpdatedScript $PSCommandPath
        $Arguments = ""
        $ScriptPart = 0

        # Find the first non-escaped space. This separates the script filename from the rest of the arguments.
        do {
            # If we find an escape character, jump over the character it's escaping.
            if($MyInvocation.Line[$ScriptPart] -eq "``") { $ScriptPart++ }
            $ScriptPart++
        } while($ScriptPart -lt $MyInvocation.Line.Length -and $MyInvocation.Line[$ScriptPart] -ne " ")

        # If we found an unescaped space, there are arguments -- extract them.
        if($ScriptPart -lt $MyInvocation.Line.Length) {
            $Arguments = $MyInvocation.Line.Substring($ScriptPart)
        }

        # Convert the script from a potentially relative path to a known-absolute path.
        # PSCommandPath does not escape spaces, so we need to do that.
        $Script = $PSCommandPath.Replace(" ", "`` ")

        Write-Host "Running the updated script."
        # Reconstruct a new, well-escaped, absolute-pathed, unrestricted call to PowerShell
        Start-Process "$psHome\powershell.exe" -ArgumentList ("-executionpolicy unrestricted " + $Script + $Arguments)
        Exit
    } else {
        Remove-Item $UpdatedScript
    }
    Write-Host ""

    # Script stats for debugging
    Write-Transcript (Get-FileHash -Algorithm SHA512 $PSCommandPath).Hash
    Write-Transcript (Get-Item $PSCommandPath).Length
    Write-Host ""

    # Initial sanity checks

    $ScriptDrive = [System.IO.DriveInfo]::GetDrives() |? { (Split-Path -Path $_.Name -Qualifier) -eq (Split-Path -Path $PSScriptRoot -Qualifier) }

    if ($ScriptDrive.DriveFormat -ne "NTFS") {
        Write-Host "This script must be run from an NTFS filesystem, as it can potentially cache very large files."
        exit
    }

    # Perform an advisory space check
    $EstimatedCacheSpace =  (1024*1024*1024*1.5) + # Estimated unpacked driver size
                            (1024*1024*1024*16) +  # Estimated exported WIM size
                            (1024*1024*100)        # Estimated unpacked SRSv2 kit size
    if ($ScriptDrive.AvailableFreeSpace -lt $EstimatedCacheSpace) {
        Write-Warning "The drive this script is running from may not have enough free space for the script to complete successfully."
        Write-Warning ("You should ensure at least {0:F2}GiB are available before continuing." -f ($EstimatedCacheSpace / (1024*1024*1024)) )
        Write-Warning "Would you like to proceed anyway?"
        do {
            $confirmation = (Read-Host -Prompt "YES or NO")
            if ($confirmation -eq "YES") {
                Write-Warning "Proceeding despite potentially insufficient scratch space."
                break
            }

            if ($confirmation -eq "NO") {
                Write-Host "Please re-run the script after you make more space available on the current drive, or move the script to a drive with more available space."
                exit
            }

            Write-Host "Invalid option."
        } while ($true)
    }

    # Determine OEM status
    $IsOem = $null
    if ($Manufacturing) {
        $IsOem = $true
    }
    while ($IsOem -eq $null) {
        Write-Host "What type of customer are you?"
        switch (Read-Host -Prompt "OEM or Enterprise") {
            "OEM" {
                $IsOem = $true
                Write-Transcript "OEM selected."
            }

            "Enterprise" {
                $IsOem = $false
                Write-Transcript "Enterprise selected."
            }

            Default {
                $IsOem = $null
            }
        }
    }


    if ($true) {
        $i = 1

        Write-Host ("Please make sure you have all of the following available:")
        Write-Host ("")
        Write-Host ("{0}. A USB drive with sufficient space (16GB+)." -f $i++)
        Write-Host ("   The contents of this drive WILL BE LOST!")
    if ($IsOem) {
        Write-Host ("{0}. Windows 10 Enterprise IoT media that matches your SRSv2 deployment kit." -f $i++)
    } else {
        Write-Host ("{0}. Windows 10 Enterprise media that matches your SRSv2 deployment kit." -f $i++)
    }
        PrintWhereToGetMedia -IsOem:$IsOem
        Write-Host ("{0}. Any language pack (LP and/or LIP) files to be included." -f $i++)
        PrintWhereToGetLangpacks -IsOem:$IsOem
        Write-Host ("")
        Write-Host ("Please do not continue until you have all these items in order.")
        Write-Host ("")
    }


    # Acquire the SRS deployment kit
    $SRSDK = Save-Url "https://go.microsoft.com/fwlink/?linkid=851168" "deployment kit"
    Test-Signature $SRSDK


    ## Extract the deployment kit.
    $RigelMedia = Join-Path $PSScriptRoot "SRSv2"

    if (Test-Path $RigelMedia) {
      Remove-Directory $RigelMedia
    }

    Write-Host "Extracting the deployment kit... " -NoNewline
    Expand-Archive $SRSDK $RigelMedia
    Write-Host "done."


    ## Pull relevant values from the deployment kit
    $RigelMedia = Join-Path $RigelMedia "Skype Room System Deployment Kit"

    $UnattendConfigFile = ([io.path]::Combine($RigelMedia, '$oem$', '$1', 'Rigel', 'x64', 'Scripts', 'Provisioning', 'config.json'))
    $UnattendConfig = @{}

    if ((Test-Path $UnattendConfigFile)) {
        $UnattendConfig = ConvertFrom-PSCustomObject (Get-Content $UnattendConfigFile | ConvertFrom-Json)
    }

    # Acquire the driver pack
    # We have to do this first now, in order to tell what OS-specific config files to pick out of the kit.
    Write-Host ""
    Write-Host "Please indicate what drivers you wish to use with this installation."
    $Variables = @{}
    $DriverPacks = Render-Menu -MenuItem $UnattendConfig["Drivers"]["RootItem"] -MenuItems $UnattendConfig["Drivers"]["MenuItems"] -Variables $Variables

    $BIOS = $false

    if ($Variables.ContainsKey("BIOS")) {
        $BIOS = $Variables["BIOS"]
    }

    # Determine the major OS. Default to 10 if not specified.
    $MajorOs = "10"
    if ($Variables.ContainsKey("OS")) {
        $MajorOs = $Variables["OS"]
    }

    # Swap in the set of variables for this major OS.
    # Use the root config by default if no OS subsection present.
    $MajorOsConfig = $UnattendConfig
    if ($UnattendConfig.ContainsKey("Win")) {
        $MajorOsConfig = $UnattendConfig["Win"][$MajorOs]
    }

    # If alternate config files are selected, copy them to the
    # root location, where they're expected to be.
    if ($MajorOsConfig.ContainsKey("AutoUnattend")) {
        $MajorOsConfigDir = ([io.path]::Combine($RigelMedia, "Provisioning", $MajorOsConfig["AutoUnattend"]))
        Copy-Item (Join-Path $MajorOsConfigDir "*.*") $RigelMedia -Force | Write-Debug
    }

    $UnattendFile = Join-Path $RigelMedia "AutoUnattend.xml"

    $xml = New-Object System.Xml.XmlDocument
    $XmlNs = @{"u"="urn:schemas-microsoft-com:unattend"}
    $xml.Load($UnattendFile)

    $SrsKitOs = (Select-Xml -Namespace $XmlNs -Xml $xml -XPath "//u:assemblyIdentity/@version").Node.Value

    # The language pack version should match the unattend version.
    $LangPackVersion = $SrsKitOs

    # In some cases, AutoUnattend does not/can not match the required
    # language pack's reported version number. In those cases, the correct
    # language pack version is explicitly specified in the config file.
    if ($MajorOsConfig.ContainsKey("LPVersion")) {
        $LangPackVersion = $MajorOsConfig["LPVersion"]
    }

    # In some cases, AutoUnattend does not/can not match the required media's
    # reported version number. In those cases, the correct media version is
    # explicitly specified in the config file.
    if ($MajorOsConfig.ContainsKey("MediaVersion")) {
        $SrsKitOs = $MajorOsConfig["MediaVersion"]
    }

    # Acquire detailed OS version and location information.
    $script:SrsKitHumanVersion = $MajorOsConfig["HumanVersion"]
    $SrsKitEffectiveVersion = $MajorOsConfig["EffectiveVersion"]
    $script:SrsKitVlscName = $MajorOsConfig["VlscName"]
    if ($IsOem) {
        $script:SrsKitIsoSize = $MajorOsConfig["OemSize"]
        $script:SrsKitIsoSha256 = $MajorOsConfig["OemSha256"]
    } else {
        $script:SrsKitIsoSize = $MajorOsConfig["VlscSize"]
        $script:SrsKitIsoSha256 = $MajorOsConfig["VlscSha256"]
    }

    # Now that we know what OS needs to be used, print out the full details.
    PrintWhereToGetMedia
    Write-Host ""

    $DriverDest = ((Select-Xml -Namespace $XmlNs -Xml $xml -XPath "//u:DriverPaths/u:PathAndCredentials/u:Path/text()").ToString())


    # Prevent old tools (e.g., DISM) from messing up images that are newer than the tool itself,
    # and creating difficult-to-debug images that look like they work right up until you can't
    # actually install them.
    if ($ActualRuntime -lt $SrsKitEffectiveVersion) {
        Write-Host ""
        Write-Host "The host OS this script is running from must be at least as new as the target"
        Write-Host "OS required by the deployment kit. Please update this machine to at least"
        Write-Host "Windows version $SrsKitEffectiveVersion and then re-run this script."
        Write-Host ""
        Write-Error "Current host OS is older than target OS version."
        exit
    }

    $DriverDest = $DriverDest.Replace("%configsetroot%", $RigelMedia)

    ## Extract the driver pack
    $DriverMedia = Join-Path $PSScriptRoot "Drivers"

    if (Test-Path $DriverMedia) {
      Remove-Directory $DriverMedia
    }

    New-Item -ItemType Directory $DriverMedia | Write-Debug

    ForEach ($DriverPack in $DriverPacks) {
        $Target = Join-Path $DriverMedia (Get-Item $DriverPack).BaseName
        Write-Host ("Extracting {0}... " -f (Split-Path $DriverPack -Leaf)) -NoNewline
        Expand-Archive $DriverPack $Target
        Write-Host "done."
    }

    # Acquire the language packs
    $LanguagePacks = @(Get-Item -Path (Join-Path $PSScriptRoot "*.cab"))
    $InstallLP = New-Object System.Collections.ArrayList
    $InstallLIP = New-Object System.Collections.ArrayList

    Write-Host "Identifying language packs... "
    ForEach ($LanguagePack in $LanguagePacks) {
        $package = $null
        try {
            $package = (Get-WindowsPackage -Online -PackagePath $LanguagePack)
        } catch {
            Write-Warning "$LanguagePack is not a language pack."
            continue
        }
        if ($package.ReleaseType -ine "LanguagePack") {
            Write-Warning "$LanguagePack is not a language pack."
            continue
        }
        $parts = $package.PackageName.Split("~")
        if ($parts[2] -ine "amd64") {
            Write-Warning "$LanguagePack is not for the right architecture."
            continue
        }
        if ($parts[4] -ine $LangPackVersion) {
            Write-Warning "$LanguagePack is not for the right OS version."
            continue
        }
        $type = ($package.CustomProperties |? {$_.Name -ieq "LPType"}).Value
        if ($type -ieq "LIP") {
            $InstallLIP.Add($LanguagePack) | Write-Debug
        } elseif ($type -ieq "Client") {
            $InstallLP.Add($LanguagePack) | Write-Debug
        } else {
            Write-Warning "$LanguagePack is of unknown type."
        }
    }
    Write-Host "... done identifying language packs."


    # Acquire the updates
    $InstallUpdates = New-Object System.Collections.ArrayList

    # Only get updates if the MSI indicates they're necessary.
    if ($MajorOsConfig.ContainsKey("RequiredUpdates")) {
        $MajorOsConfig["RequiredUpdates"].Keys |% {
            $URL = $MajorOsConfig["RequiredUpdates"][$_]
            $File = Save-Url $URL "update $_"
            $InstallUpdates.Add($File) | Write-Debug
        }
    }

    # Verify signatures on whatever updates were aquired.
    foreach ($update in $InstallUpdates) {
        Test-Signature $update
    }

    if ($InstallLP.Count -eq 0 -and $InstallLIP.Count -eq 0 -and $InstallUpdates -ne $null) {
        Write-Warning "THIS IS YOUR ONLY CHANCE TO PRE-INSTALL LANGUAGE PACKS."
        Write-Host "Because you are pre-installing an update, you will NOT be able to pre-install language packs to the image at a later point."
        Write-Host "You are currently building an image with NO pre-installed language packs."
        Write-Host "Are you ABSOLUTELY SURE this is what you intended?"

        do {
            $confirmation = (Read-Host -Prompt "YES or NO")
            if ($confirmation -eq "YES") {
                Write-Warning "PROCEEDING TO GENERATE SLIPSTREAM IMAGE WITH NO PRE-INSTALLED LANGUAGE PACKS."
                break
            }

            if ($confirmation -eq "NO") {
                Write-Host "Please place the LP and LIP cab files you wish to use in this directory, and run the script again."
                Write-Host ""
                Write-Host "You can download language packs from the following locations:"
                PrintWhereToGetLangpacks -IsOem:$IsOem
                exit
            }

            Write-Host "Invalid option."
        } while ($true)
    }

    # Discover and prompt for selection of a reasonable target drive
    $TargetDrive = $null

    $TargetType = "USB"
    if ($Manufacturing) {
        $TargetType = "File Backed Virtual"
    }
    $ValidTargetDisks = @((Get-Disk) |? {$_.BusType -eq $TargetType})

    if ($ValidTargetDisks.Count -eq 0) {
        Write-Host "You do not have any valid media plugged in. Ensure that you have a removable drive inserted into the computer."
        exit
    }

    Write-Host ""
    Write-Host "Reminder: all data on the drive you select will be lost!"
    Write-Host ""

    $TargetDisk = ($ValidTargetDisks[(Get-TextListSelection -Options $ValidTargetDisks -Property "FriendlyName" -Prompt "Please select a target drive" -AllowDefault:$false)])

    # Acquire the Windows install media root
    do {
        # Trim off leading/trailing quote marks, as pasting in a copied-as-path string will have.
        $WindowsIso = (Read-Host -Prompt "Please enter the path to the Windows install ISO file").Trim('"')
    } while ([string]::IsNullOrEmpty($WindowsIso) -or !(Test-OsIsoPath -OsIsoPath $WindowsIso -KitIsoSize $script:SrsKitIsoSize -KitIsoSha256 $script:SrsKitIsoSha256 -IsOem:$IsOem))

    $WindowsIsoMount = Mount-DiskImage $WindowsIso
    $WindowsMedia = ($WindowsIsoMount | Get-Volume).DriveLetter + ":"

    # All non-VL keys are OA3.0 based now
    $LicenseKey = ""

    if ($Manufacturing) {
        $LicenseKey = "XQQYW-NFFMW-XJPBH-K8732-CKFFD"
    } elseif ($IsOem) {
        $LicenseKey = "XQQYW-NFFMW-XJPBH-K8732-CKFFD"
    }

    ###
    ## Let the user know what we've discovered
    ###

    Write-Host ""
    if ($IsOem) {
        Write-Host "Creating OEM media."
    } else {
        Write-Host "Creating Enterprise media."
    }
    Write-Host ""
    if ($BIOS) {
        Write-Host "Creating BIOS-compatible media."
    } else {
        Write-Host "Creating UEFI-compatible media."
    }
    Write-Host ""
    Write-Host "Using SRSv2 kit:      " $SRSDK
    Write-Host "Using driver packs:   "
    ForEach ($pack in $DriverPacks) {
        Write-Host "    $pack"
    }
    Write-Host "Using Windows ISO:    " $WindowsIso
    Write-Host "ISO mounted at:       " $WindowsMedia

    Write-Host "Using language packs: "
    ForEach ($pack in $InstallLP) {
        Write-Host "    $pack"
    }
    ForEach ($pack in $InstallLIP) {
        Write-Host "    $pack"
    }

    Write-Host "Using updates:        "
    ForEach ($update in $InstallUpdates) {
        Write-Host "    $update"
    }
    Write-Host "Writing stick:        " $TargetDisk.FriendlyName
    Write-Host ""


    ###
    ## Make the stick.
    ###


    # Partition & format
    Write-Host "Formatting and partitioning the target drive... " -NoNewline
    Get-Disk $TargetDisk.DiskNumber | Initialize-Disk -PartitionStyle MBR -ErrorAction SilentlyContinue
    Clear-Disk -Number $TargetDisk.DiskNumber -RemoveData -RemoveOEM -Confirm:$false
    Get-Disk $TargetDisk.DiskNumber | Initialize-Disk -PartitionStyle MBR -ErrorAction SilentlyContinue
    Get-Disk $TargetDisk.DiskNumber | Set-Disk -PartitionStyle MBR

    ## Windows refuses to quick format FAT32 over 32GB in size.
    $part = $null
    try {
        ## For disks >= 32GB
        $part = New-Partition -DiskNumber $TargetDisk.DiskNumber -Size 32GB -AssignDriveLetter -IsActive -ErrorAction Stop
    } catch {
        ## For disks < 32GB
        $part = New-Partition -DiskNumber $TargetDisk.DiskNumber -UseMaximumSize -AssignDriveLetter -IsActive -ErrorAction Stop
    }

    $part | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "SRSV2" -Confirm:$false | Write-Debug

    $TargetDrive = ("{0}:\" -f $part.DriveLetter)
    Write-Host "done."

    # Windows
    Write-Host "Copying Windows... " -NoNewline
    ## Exclude install.wim, since apparently some Windows source media are not USB EFI compatible (?) and have WIMs >4GB in size.
    SyncDirectory -Src $WindowsMedia -Dst $TargetDrive -Flags @("/xf", "install.wim")
    Write-Host "done."

    $NewInstallWim = (Join-Path $PSScriptRoot "install.wim")
    $InstallWimMnt = (Join-Path $PSScriptRoot "com-mnt")
    $SourceName = "Windows $MajorOs Enterprise"

    try {
        Write-Host "Copying the installation image... " -NoNewline
        Export-WindowsImage -DestinationImagePath "$NewInstallWim" -SourceImagePath (Join-Path (Join-Path $WindowsMedia "sources") "install.wim") -SourceName $SourceName | Write-Debug
        Write-Host "done."

        # Image update
        if ($InstallLP.Count -gt 0 -or $InstallLIP.Count -gt 0 -or $InstallUpdates -ne $null) {
            mkdir $InstallWimMnt | Write-Debug
            Write-Host "Mounting the installation image... " -NoNewline
            Mount-WindowsImage -ImagePath "$NewInstallWim" -Path "$InstallWimMnt" -Name "Windows 10 Enterprise" | Write-Debug
            Write-Host "done."

            Write-Host "Applying language packs... " -NoNewline
            ForEach ($pack in $InstallLP) {
                Add-WindowsPackage -Path "$InstallWimMnt" -PackagePath "$pack" -ErrorAction Stop | Write-Debug
            }
            ForEach ($pack in $InstallLIP) {
                Add-WindowsPackage -Path "$InstallWimMnt" -PackagePath "$pack" -ErrorAction Stop | Write-Debug
            }
            Write-Host "done."

            Write-Host "Applying updates... " -NoNewline
            ForEach ($update in $InstallUpdates) {
                Add-WindowsPackage -Path "$InstallWimMnt" -PackagePath "$update" -ErrorAction Stop | Write-Debug
            }
            Write-Host "done."

            Write-Host ""
            Write-Warning "PLEASE WAIT PATIENTLY"
            Write-Host "This next part can, on some hardware, take multiple hours to complete."
            Write-Host "Aborting at this point will result in NON-FUNCTIONAL MEDIA."
            Write-Host "To minimize wait time, consider hardware improvements:"
            Write-Host "  - Use a higher (single-core) performance CPU"
            Write-Host "  - Use a fast SSD, connected by a fast bus (6Gbps SATA, 8Gbps NVMe, etc.)"
            Write-Host ""

            Write-Host "Cleaning up the installation image... " -NoNewline
            Set-ItemProperty (Join-Path (Join-Path $TargetDrive "sources") "lang.ini") -name IsReadOnly -value $false
            Invoke-Native "& dism /quiet /image:$InstallWimMnt /gen-langini /distribution:$TargetDrive"
            Invoke-Native "& dism /quiet /image:$InstallWimMnt /cleanup-image /startcomponentcleanup /resetbase"
            Write-Host "done."

            Write-Host "Unmounting the installation image... " -NoNewline
            Dismount-WindowsImage -Path $InstallWimMnt -Save | Write-Debug
            rmdir $InstallWimMnt
            Write-Host "done."
        }

        Write-Host "Splitting the installation image... " -NoNewline
        Split-WindowsImage -ImagePath "$NewInstallWim" -SplitImagePath (Join-Path (Join-Path $TargetDrive "sources") "install.swm") -FileSize 2047 | Write-Debug
        del $NewInstallWim
        Write-Host "done."
    } catch {
        try { Dismount-WindowsImage -Path $InstallWimMnt -Discard -ErrorAction SilentlyContinue } catch {}
        del $InstallWimMnt -Force -ErrorAction SilentlyContinue
        del $NewInstallWim -Force -ErrorAction SilentlyContinue
        throw
    }

    # Drivers
    Write-Host "Injecting drivers... " -NoNewline
    SyncSubdirectories -Src $DriverMedia -Dst $DriverDest
    Write-Host "done."

    # Rigel
    Write-Host "Copying Rigel build... " -NoNewline
    SyncSubdirectories -Src $RigelMedia -Dst $TargetDrive
    Copy-Item (Join-Path $RigelMedia "*.*") $TargetDrive | Write-Debug
    Write-Host "done."

    # Snag and update the unattend
    Write-Host "Configuring unattend files... " -NoNewline

    $RootUnattendFile = ([io.path]::Combine($TargetDrive, 'AutoUnattend.xml'))
    $InnerUnattendFile = ([io.path]::Combine($TargetDrive, '$oem$', '$1', 'Rigel', 'x64', 'Scripts', 'Provisioning', 'AutoUnattend.xml'))

    ## Handle the root unattend
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($RootUnattendFile)
    if ($IsOem) {
        Add-AutoUnattend-Key $xml $LicenseKey
    }
    Set-AutoUnattend-Sysprep-Mode -Xml $xml -Shutdown
    Set-AutoUnattend-Partitions -Xml $xml -BIOS:$BIOS
    $xml.Save($RootUnattendFile)

    ## Handle the inner unattend
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($InnerUnattendFile)
    if ($IsOem) {
        Add-AutoUnattend-Key $xml "XQQYW-NFFMW-XJPBH-K8732-CKFFD"
    }
    Set-AutoUnattend-Sysprep-Mode -Xml $xml -Reboot
    Set-AutoUnattend-Partitions -Xml $xml -BIOS:$BIOS
    $xml.Save($InnerUnattendFile)

    Write-Host "done."

    # Let Windows setup know what kind of license key to check for.
    Write-Host "Selecting image... " -NoNewline
    $TargetEICfg = (Join-Path (Join-Path $TargetDrive "sources") "EI.cfg")
    $OEMEICfg = @"
[EditionID]
Enterprise
[Channel]
OEM
[VL]
0
"@
    $EnterpriseEICfg = @"
[EditionID]
Enterprise
[Channel]
Retail
[VL]
1
"@
    if ($IsOem) {
        $OEMEICfg | Out-File -FilePath $TargetEICfg -Force
    } else {
        $EnterpriseEICfg | Out-File -FilePath $TargetEICfg -Force
    }
    Write-Host "done."


    Write-Host "Cleaning up... " -NoNewline

    Remove-Directory $DriverMedia
    Remove-Directory $RigelMedia

    # This folder can sometimes cause copy errors during Windows Setup, specifically when Setup is creating the ConfigSet folder.
    Remove-Item (Join-Path $TargetDrive "System Volume Information") -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "done."


    Write-Host ""
    Write-Host "Please safely eject your USB stick before removing it."

    if ($InstallUpdates -ne $null) {
        Write-Warning "DO NOT PRE-INSTALL LANGUAGE PACKS AFTER THIS POINT"
        Write-Warning "You have applied a Windows Update to this media. Any pre-installed language packs must be added BEFORE Windows updates."
    }
} finally {
    try {
        if ($WindowsIsoMount -ne $null) {
            $WindowsIsoMount | Dismount-DiskImage | Write-Debug
        }
    } catch {}
    Stop-Transcript
}
# SIG # Begin signature block
# MIInzgYJKoZIhvcNAQcCoIInvzCCJ7sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCx7nQJQH0ZSlGs
# F9It5f19/bzd98Kv5iibQkOBeo6nIqCCDYUwggYDMIID66ADAgECAhMzAAACzfNk
# v/jUTF1RAAAAAALNMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NjAyWhcNMjMwNTExMjA0NjAyWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDrIzsY62MmKrzergm7Ucnu+DuSHdgzRZVCIGi9CalFrhwtiK+3FIDzlOYbs/zz
# HwuLC3hir55wVgHoaC4liQwQ60wVyR17EZPa4BQ28C5ARlxqftdp3H8RrXWbVyvQ
# aUnBQVZM73XDyGV1oUPZGHGWtgdqtBUd60VjnFPICSf8pnFiit6hvSxH5IVWI0iO
# nfqdXYoPWUtVUMmVqW1yBX0NtbQlSHIU6hlPvo9/uqKvkjFUFA2LbC9AWQbJmH+1
# uM0l4nDSKfCqccvdI5l3zjEk9yUSUmh1IQhDFn+5SL2JmnCF0jZEZ4f5HE7ykDP+
# oiA3Q+fhKCseg+0aEHi+DRPZAgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQU0WymH4CP7s1+yQktEwbcLQuR9Zww
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzQ3MDUzMDAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AE7LSuuNObCBWYuttxJAgilXJ92GpyV/fTiyXHZ/9LbzXs/MfKnPwRydlmA2ak0r
# GWLDFh89zAWHFI8t9JLwpd/VRoVE3+WyzTIskdbBnHbf1yjo/+0tpHlnroFJdcDS
# MIsH+T7z3ClY+6WnjSTetpg1Y/pLOLXZpZjYeXQiFwo9G5lzUcSd8YVQNPQAGICl
# 2JRSaCNlzAdIFCF5PNKoXbJtEqDcPZ8oDrM9KdO7TqUE5VqeBe6DggY1sZYnQD+/
# LWlz5D0wCriNgGQ/TWWexMwwnEqlIwfkIcNFxo0QND/6Ya9DTAUykk2SKGSPt0kL
# tHxNEn2GJvcNtfohVY/b0tuyF05eXE3cdtYZbeGoU1xQixPZAlTdtLmeFNly82uB
# VbybAZ4Ut18F//UrugVQ9UUdK1uYmc+2SdRQQCccKwXGOuYgZ1ULW2u5PyfWxzo4
# BR++53OB/tZXQpz4OkgBZeqs9YaYLFfKRlQHVtmQghFHzB5v/WFonxDVlvPxy2go
# a0u9Z+ZlIpvooZRvm6OtXxdAjMBcWBAsnBRr/Oj5s356EDdf2l/sLwLFYE61t+ME
# iNYdy0pXL6gN3DxTVf2qjJxXFkFfjjTisndudHsguEMk8mEtnvwo9fOSKT6oRHhM
# 9sZ4HTg/TTMjUljmN3mBYWAWI5ExdC1inuog0xrKmOWVMIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGZ8wghmbAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAALN82S/+NRMXVEAAAAA
# As0wDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIAxc
# 4BpezkHeeud4vCnSwwRMInK0avrkQY3zN0iUXp0zMEIGCisGAQQBgjcCAQwxNDAy
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20wDQYJKoZIhvcNAQEBBQAEggEAETboP6Qer2ZhwDTF5Vi+CPRewgjJtpFVxqUA
# 1v9cNXM9JHgNaKsvhDF0jcZ/NAFSqzrR+5XNIix8KTJOD759M/gyIoD6uDPdrK/u
# nxfHiipVPUL4ClowJPwmLv2HJQvgwx5HFEMxmpUsHIl9h6ZUeeolixnrPiWB4kEs
# 27o8dgHUmzuKjh3PxZ9ux117zFfYizANMHI7ys4ByozHoORMIPKpl/Ixn6YidXOF
# oQ8TK/Jj7UjotZpvphsZLCiSCgvFO0m3S5mvyUpXDT1qtYsAMC3KRxudtvmhu7YZ
# YTy+kyqnV3Qtdo5ePvpBLXwx/uSZvbG5VmLZagtYUksDcdmmU6GCFykwghclBgor
# BgEEAYI3AwMBMYIXFTCCFxEGCSqGSIb3DQEHAqCCFwIwghb+AgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYKKwYBBAGE
# WQoDATAxMA0GCWCGSAFlAwQCAQUABCBfP7AVk9X1m2TBEoxdILDgmXq6hwH5392P
# ipQB+lQkMgIGY/dZSU6WGBMyMDIzMDMxNjE2NTMzOS4wNDRaMASAAgH0oIHYpIHV
# MIHSMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsT
# HVRoYWxlcyBUU1MgRVNOOjg2REYtNEJCQy05MzM1MSUwIwYDVQQDExxNaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIReDCCBycwggUPoAMCAQICEzMAAAG3ISca
# B6IqhkYAAQAAAbcwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTAwHhcNMjIwOTIwMjAyMjE0WhcNMjMxMjE0MjAyMjE0WjCB0jELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9z
# b2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjo4NkRGLTRCQkMtOTMzNTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMf9
# z1dQNBNkTBq3HJclypjQcJIlDAgpvsw4vHJe06n532RKGkcn0V7p65OeA1wOoO+8
# NsopnjPpVZ8+4s/RhdMCMNPQJXoWdkWOp/3puIEs1fzPBgTJrdmzdyUYzrAloICY
# x722gmdpbNf3P0y5Z2gRO48sWIYyYeNJYch+ZfJzXqqvuvq7G8Nm8IMQi8Zayvx+
# 5dSGBM5VYHBxCEjXF9EN6Qw7A60SaXjKjojSpUmpaM4FmVec985PNdSh8hOeP2tL
# 781SBan92DT19tfNHv9H0FAmE2HGRwizHkJ//mAZdS0s6bi/UwPMksAia5bpnIDB
# OoaYdWkV0lVG5rN0+ltRz9zjlaH9uhdGTJ+WiNKOr7mRnlzYQA53ftSSJBqsEpTz
# Cv7c673fdvltx3y48Per6vc6UR5e4kSZsH141IhxhmRR2SmEabuYKOTdO7Q/vlvA
# fQxuEnJ93NL4LYV1IWw8O+xNO6gljrBpCOfOOTQgWJF+M6/IPyuYrcv79Lu7lc67
# S+U9MEu2dog0MuJIoYCMiuVaXS5+FmOJiyfiCZm0VJsJ570y9k/tEQe6aQR9MxDW
# 1p2F3HWebolXj9su7zrrElNlHAEvpFhcgoMniylNTiTZzLwUj7TH83gnugw1FCEV
# Vh5U9lwNMPL1IGuz/3U+RT9wZCBJYIrFJPd6k8UtAgMBAAGjggFJMIIBRTAdBgNV
# HQ4EFgQUs/I5Pgw0JAVhDdYB2yPII8l4tOwwHwYDVR0jBBgwFoAUn6cVXQBeYl2D
# 9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUy
# MDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUB
# Af8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQAD
# ggIBAA2dZMybhVxSXTbJzFgvNiMCV5/Ayn5UuzJU495YDtcefold0ehR9QBGBhHm
# AMt10WYCHz2WQUyM3mQD4IsHfEL1JEwgG9tGq71ucn9dknLBHD30JvbQRhIKcvFS
# nvRCCpVpilM8F/YaWXC9VibSef/PU2GWA+1zs64VFxJqHeuy8KqrQyfF20SCnd8z
# RZl4YYBcjh9G0GjhJHUPAYEx0r8jSWjyi2o2WAHD6CppBtkwnZSf7A68DL4OwwBp
# mFB3+vubjgNwaICS+fkGVvRnP2ZgmlfnaAas8Mx7igJqciqq0Q6An+0rHj1kxisN
# dIiTzFlu5Gw2ehXpLrl59kvsmONVAJHhndpx3n/0r76TH+3WNS9UT9jbxQkE+t2t
# hif6MK5krFMnkBICCR/DVcV1qw9sg6sMEo0wWSXlQYXvcQWA65eVzSkosylhIlIZ
# ZLL3GHZD1LQtAjp2A5F7C3Iw4Nt7C7aDCfpFxom3ZulRnFJollPHb3unj9hA9xvR
# iKnWMAMpS4MZAoiV4O29zWKZdUzygp7gD4WjKK115KCJ0ovEcf92AnwMAXMnNs1o
# 0LCszg+uDmiQZs5eR7jzdKzVfF1z7bfDYNPAJvm5pSQdby3wIOsN/stYjM+EkaPt
# Uzr8OyMwrG+jpFMbsB4cfN6tvIeGtrtklMJFtnF68CcZZ5IAMIIHcTCCBVmgAwIB
# AgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0
# IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1
# WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O
# 1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZn
# hUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t
# 1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxq
# D89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmP
# frVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSW
# rAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv
# 231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zb
# r17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYcten
# IPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQc
# xWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17a
# j54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQAB
# MCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQU
# n6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEw
# QTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9E
# b2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/
# MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJ
# oEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYB
# BQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3h
# LB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x
# 5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74p
# y27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1A
# oL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbC
# HcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB
# 9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNt
# yo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3
# rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcV
# v7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A24
# 5oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lw
# Y1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAtQwggI9AgEBMIIBAKGB2KSB1TCB
# 0jELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMk
# TWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMSYwJAYDVQQLEx1U
# aGFsZXMgVFNTIEVTTjo4NkRGLTRCQkMtOTMzNTElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAyGdBGMObODlsGBZm
# SUX2oWgfqcaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAN
# BgkqhkiG9w0BAQUFAAIFAOe9hlEwIhgPMjAyMzAzMTYyMDEzMDVaGA8yMDIzMDMx
# NzIwMTMwNVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA572GUQIBADAHAgEAAgIC
# SDAHAgEAAgITFzAKAgUA577X0QIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GB
# AOKNKuxcuef8cmEep8DK6QHWxJNwlqW7Z26X7ab+vC8bmmfR852w5NVXC+n/xSZb
# 76CaDdDFZ/uzEhXT+ML7czlGmjSAHtgJMkJAf+Jv5739IOWmURaENvtZjMWY3EQk
# UN1soZ101Z/3xoTEDQzPhIV0HYdBauI7tef9vVkXpVkLMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAG3IScaB6IqhkYAAQAA
# AbcwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgXa47LmAdgyo//OsmlPBw9mV1FQViFsNQ5o1k3Aus
# PagwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBsJ3jTsh7aL8hNeiYGL5/8
# IBn8zUfr7/Q7rkM8ic1wQTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAABtyEnGgeiKoZGAAEAAAG3MCIEILoAFfzu8hrDMaUsELUeccIu
# AkOgu8LbkDajKBjsZTHCMA0GCSqGSIb3DQEBCwUABIICAMNt3IJhjvCV5ABi171d
# v6v+iMPwNt1sWIZRiDOT4p8pYVp5g3IId7q3kk3DpJzxKlg2msVVV2/C4Q6bCbLR
# AbWHXdka9cGVwuCEllRc99pYNn85bS190OCwA7SDkJ3BlvAYc3dWz664Gai4gciq
# uUPN2j7/uGfOovZ11Fq3z8STU6aW4xykuCQ66u01TIDctqvMr3QmlOkWwz+lG4fE
# TLHHpuyuwognuUBoU9jtMjn94aARXmu364QKjyVnDD519gDWfnVOIb0ZWpcxC+M7
# gQxUI1XZ25PbN+D2OG175xwG4+4O635la1Y4hM0266zz9lSjEZclA5Nu0HG9iGUU
# 1Qg05EAGwRWrfqRTI60v6g8p8QRBjf4NSpdJqUpnmvKxD+EiiKqiGhSagTuKeR52
# jbL1VU41j/dg6MmvVMOlMwr2Ic1/OfNuSsWOzeXnH/vAAvoG3UBNCg6KFcNG8CMx
# aRF0/9NrH+ICMnMGTe/TrAM7XmTw+8yOrOubUAcqn3YDqoh1ZsLcQWRKHFaYt02D
# 3Hl6p9Ozz92eSZsYgohka6P46JWC4+S8neej9KiJSkJgy2v4woxJvgk1n6u8uhWG
# XjsEEid9W6bGH5OqF4vONRUBL+8rzuZcXpVZ4au93yVZ5bVkZ0NGAHAL5w7coMFk
# eDJ4GizBDZfoOCRycN9zJk6L
# SIG # End signature block
