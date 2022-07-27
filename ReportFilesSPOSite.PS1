# ReportFilesSPOSite.PS1
# A demo script to show how to generate a report of the files in a SharePoint Online site using the 
# Microsoft Graph
# https://github.com/12Knocksinna/Office365itpros/blob/master/ReportFilesSPOSite.PS1
# V1.0 04-July-2022
# .\ReportFilesSPOSite.PS1 -SearchSite "Billing"

Param ([Parameter(Mandatory)]$SearchSite)

function GetFilesFromFolder {
# Unpack set of files from a folder
param (
        [parameter(Mandatory = $true)]
        $BaseUri,

        [parameter(Mandatory = $true)]
        $FolderName,
		
		[parameter(Mandatory = $true)]
        $FolderFiles
    )

  #Write-Host "Processing sub-folder" $FolderName
  $Uri = $BaseUri + "/" + $FolderName + ":/children"
  $FolderData = Invoke-MgGraphRequest -Uri $Uri -Method Get
  
  ForEach ($D in $FolderData.Value) {
    If ($D.folder.childcount -eq $Null) { # Process files found in folder
       # Format file size nicely
      $FileSize = FormatFileSize $D.Size
      $ReportLine  = [PSCustomObject] @{   
         FileName = $D.Name
         Folder   = $FolderName 
         Author   = $D.createdby.user.displayname
         Created  = $D.createdDateTime
         Modified = $D.lastModifiedDateTime
         Size     = $FileSize
         Uri      = $D.WebUrl }
      [System.Collections.Generic.List[Object]]$FolderFiles.Add($ReportLine) 
    } # End If

    ElseIf ($D.folder.childcount -gt 0) { # Process sub-folders found in folder
	  $NewFolderName = $FolderName + "/" + $D.Name
	  GetFilesFromFolder -BaseUri $BaseUri -FolderName $NewFolderName -FolderFiles $FolderFiles
	} # End ElseIf
  } # End ForEach
   

  # There might be more than 200 items to be fetched, so check the nextlink and continue
  # reading data until there's no more next links to follow

  $NextLink = $FolderData."@odata.nextLink"
  $Uri = $FolderData."@odata.nextLink"
  While ($NextLink) { 
    $MoreData = Invoke-MgGraphRequest -Uri $Uri -Method Get
    ForEach ($D in $MoreData.Value) {
	  If ($D.folder.childcount -eq $Null) { # Process files found in folder
        $FileSize = FormatFileSize $D.Size
        $ReportLine  = [PSCustomObject] @{   
          FileName = $D.Name
          Folder   = $Drive.Name 
          Author   = $D.createdby.user.displayname
          Created  = $D.createdDateTime
          Modified = $D.lastModifiedDateTime
          Size     = $FileSize
          Uri      = $D.WebUrl }
        $FolderFiles.Add($ReportLine) 
      } # End If
	  
	  ElseIf ($D.folder.childcount -gt 0) { # Process sub-folders found in folder
		 $NewFolderName = $FolderName + "/" + $D.Name
		 GetFilesFromFolder -BaseUri $BaseUri -FolderName $NewFolderName -FolderFiles $FolderFiles
	  } # End ElseIf
	} # End ForEach 
    
	$NextLink = $MoreData."@odata.nextLink"
    $Uri = $MoreData."@odata.nextLink" 
  } # End While

  # Write-Host "Folder has " $FolderFiles.Count " items"
  # $FolderFiles
}

function GetFilesFromFolderWithLog {
# Unpack set of files from a folder
param (
        [parameter(Mandatory = $true)]
        $BaseUri,

        [parameter(Mandatory = $true)]
        $FolderName,
		
		[parameter(Mandatory = $true)]
        $FolderFiles
    )
  $before = $FolderFiles.Count
  GetFilesFromFolder -BaseUri $BaseUri -FolderName $Folder.Name -FolderFiles $FolderFiles
  $count = $FolderFiles.Count - $before
  
  Write-Host ("  $FolderName ({0})" -f $count)
}

function ProcessResponse {
# Unpack set of items (files and folders) from a Uri
param (
        [parameter(Mandatory = $true)]
        $Items,
		
		[parameter(Mandatory = $true)]
        $BaseUri,
		
		[parameter(Mandatory = $true)]
        $DocumentLibrary,

        [parameter(Mandatory = $true)]
        $SiteFiles
    )

  [array]$Items = Invoke-MgGraphRequest -Uri $Uri -Method Get

  # Find sub-folders that we need to check for files
  $Folders = $Items.Value | ? {$_.Folder.ChildCount -gt 0 }
  # And any files in the folder
  $Files = $Items.Value | ? {$_.Folder.ChildCount -eq $Null}
  
  $before = $SiteFiles.Count
  
  # Report the files
  ForEach ($D in $Files) {
    $FileSize = FormatFileSize $D.Size
    $ReportLine  = [PSCustomObject] @{   
        FileName = $D.Name
        Folder   = $DocumentLibrary.Name
        Author   = $D.createdby.user.displayname
        Created  = $D.createdDateTime
        Modified = $D.lastModifiedDateTime
        Size     = $FileSize
        Uri      = $D.WebUrl }
     $SiteFiles.Add($ReportLine) 
  } # End If

  If ($SiteFiles.Count -gt $before) {
	$count = $SiteFiles.Count - $before
	# This will print multiple times due to nextLink
	Write-Host "Files in root: " $count
  }
  
  # Report the files in each sub-folder
  ForEach ($Folder in $Folders) {
    GetFilesFromFolderWithLog -BaseUri $BaseUri -FolderName $Folder.Name -FolderFiles $SiteFiles
  } # End Foreach Folders
}

function FormatFileSize {
# Format File Size nicely
param (
        [parameter(Mandatory = $true)]
        $InFileSize
    ) 

 If ($InFileSize -lt 1KB) { # Format the size of a document
        $FileSize = $InFileSize.ToString() + " B" } 
      ElseIf ($InFileSize -lt 1MB) {
        $FileSize = $InFileSize / 1KB
        $FileSize = ("{0:n2}" -f $FileSize) + " KB"} 
      Elseif ($InFileSize -lt 1GB) {
        $FileSize = $InFileSize / 1MB
        $FileSize = ("{0:n2}" -f $FileSize) + " MB" }
      Elseif ($InFileSize -ge 1GB) {
        $FileSize = $InFileSize / 1GB
        $FileSize = ("{0:n2}" -f $FileSize) + " GB" }
  Return $FileSize
} 

# Connect to the Microsoft Graph with the permission to read sites
Disconnect-MgGraph | Out-Null # Make sure that we sign out of existing sessions
Connect-MgGraph -Scopes Sites.Read.All
Select-MgProfile Beta

Write-Host "Looking for matching sites..."
$Uri = 'https://graph.microsoft.com/v1.0/sites?search="' + $SearchSite + '"'
[array]$Sites = Invoke-MgGraphRequest -Uri $uri -Method Get
$Sites = $Sites.Value

If (!($Sites)) { # Nothing found
     Write-Host "No matching sites found - exiting"; break }
If ($Sites.Count -eq 1) { # Only one site found - go ahead
     $Site = $Sites
     $SiteName = $Site.DisplayName
     Write-Host "Found site to process:" $SiteName }
Elseif ($Sites.Count -gt 1) { # More than one site found. Ask which to use
     CLS; Write-Host "More than one matching site was found. We need you to select a site to report."; [int]$i=1
     Write-Host " "
     ForEach ($SiteOption in $Sites) {
        Write-Host ("{0}: {1} ({2})" -f $i, $SiteOption.DisplayName, $SiteOption.Name); $i++}
        Write-Host ""
     [Int]$Answer = Read-Host "Enter the number of the site to use"
     If (($Answer -gt 0) -and ($Answer -le $i)) {
        [int]$Si = ($Answer-1)
        $SiteName = $Sites[$Si].DisplayName 
        Write-Host "OK. Selected site is" $Sites[$Si].DisplayName 
        $Site = $Sites[$Si] }
}

If (!($Site)) { 
    Write-Host ("Can't find the {0} site - script exiting" -f $Uri) ; break 
}

# Get Drives in the site
Write-Host ("Checking for document libraries in the {0} site" -f $Site.DisplayName)
$Uri = "https://graph.microsoft.com/v1.0/sites/$($Site.Id)/drives"
[array]$Drives = Invoke-MgGraphRequest -Uri $Uri -Method Get
$Drives = $Drives.Value

If (!($Drives)) { # Nothing found
     Write-Host "No matching drives found - exiting"; break }
If ($Drives.Count -eq 1) { # Only one drive found - go ahead
     $Drive = $Drives
     $DriveName = $Drive.Name
     Write-Host "Found drive to process:" $DriveName }
Elseif ($Drives.Count -gt 1) { # More than one drive found. Ask which to use
     CLS; Write-Host "More than one drive found in site. We need you to select a drive to report."; [int]$i=1
     Write-Host " "
     ForEach ($DriveOption in $Drives) {
        Write-Host ("{0}: {1}" -f $i, $DriveOption.Name); $i++}
        Write-Host ""
     [Int]$Answer = Read-Host "Enter the number of the drive to use"
     If (($Answer -gt 0) -and ($Answer -le $i)) {
        [int]$Si = ($Answer-1)
        $DriveName = $Drives[$Si].Name 
        Write-Host "OK. Selected drive is" $Drives[$Si].Name 
        $Drive = $Drives[$Si] }
}

If (!($Drive)) { 
    Write-Host ("Can't find the {0} drive - script exiting" -f $Uri) ; break 
}


# Find the default document library
$DocumentLibrary = $Drive

# Get Items in document library
$Uri = "https://graph.microsoft.com/v1.0/sites/$($Site.Id)/drives/$($DocumentLibrary.Id)/root/children"
$BaseUri = "https://graph.microsoft.com/v1.0/sites/$($Site.Id)/drives/$($DocumentLibrary.Id)/root:"

# Create outputs
$SiteFiles = [System.Collections.Generic.List[Object]]::new()

[array]$Items = Invoke-MgGraphRequest -Uri $Uri -Method Get

ProcessResponse -Items $Items -BaseUri $BaseUri -SiteFiles $SiteFiles -DocumentLibrary $DocumentLibrary

$NextLink = $Items."@odata.nextLink"
$Uri = $Items."@odata.nextLink"
While ($NextLink) { 
  $MoreData = Invoke-MgGraphRequest -Uri $Uri -Method Get
  ProcessResponse -Items $MoreData -BaseUri $BaseUri -SiteFiles $SiteFiles -DocumentLibrary $DocumentLibrary
  
  $NextLink = $MoreData."@odata.nextLink"
  $Uri = $MoreData."@odata.nextLink" 
} # End While


Write-Host ("Total files found {0}" -f $SiteFiles.Count)
$SiteFiles | Out-GridView

# An example script used to illustrate a concept. More information about the topic can be found in the Office 365 for IT Pros eBook https://gum.co/O365IT/
# and/or a relevant article on https://office365itpros.com or https://www.practical365.com. See our post about the Office 365 for IT Pros repository 
# https://office365itpros.com/office-365-github-repository/ for information about the scripts we write.

# Do not use our scripts in production until you are satisfied that the code meets the needs of your organization. Never run any code downloaded from 
# the Internet without first validating the code in a non-production environment.