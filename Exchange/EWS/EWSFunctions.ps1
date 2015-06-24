# Credits for some of the ews function ideas go to https://code.msdn.microsoft.com/office/PowerShellEWS-Search-e0f9c169

#region Dependancies
if ($hostinvocation -ne $null) {
    $ScriptPath = Split-Path $hostinvocation.MyCommand.path
}
else {
    $ScriptPath = Split-Path $script:MyInvocation.MyCommand.Path
}

$DependentFiles = @{
    [System.IO.Path]::GetFullPath("$ScriptPath\..\..\Supplemental\Test-EmailAddressFormat.ps1").ToString() = 'https://github.com/zloeber/Powershell/raw/master/Supplemental/Test-EmailAddressFormat.ps1'
    [System.IO.Path]::GetFullPath("$ScriptPath\..\..\Supplemental\Test-UserSIDFormat.ps1").ToString() = 'https://github.com/zloeber/Powershell/raw/master/Supplemental/Test-UserSIDFormat.ps1'
    [System.IO.Path]::GetFullPath("$ScriptPath\..\..\Supplemental\Get-WebFile.ps1").ToString() = 'https://github.com/zloeber/Powershell/raw/master/Supplemental/Get-WebFile.ps1'
    [System.IO.Path]::GetFullPath("$ScriptPath\..\..\Supplemental\Invoke-MSIExec.ps1").ToString() = 'https://github.com/zloeber/Powershell/raw/master/Supplemental/Invoke-MSIExec.ps1'
}

$DependenciesLoaded = $true

Foreach ($ModuleName in $DependentFiles.Keys) {
    $ModuleFileName = Split-Path $ModuleName -Leaf
    $ModuleFullLocalPath = $ScriptPath + '\' + $ModuleFileName
    $CleanedFileName = $ModuleFileName -replace '.ps1','' -replace '.dll','' -replace '.psm1',''
    $ModuleExt = $ModuleFileName -split '\.' | select -Last 1

    if ((Get-Module $CleanedFileName) -eq $null) {
        if (Test-Path $ModuleName) {
            if ($ModuleExt -eq 'ps1') {
                Write-Output "$($MyInvocation.MyCommand): Dot sourcing dependency from $ModuleName"
                . $ModuleName
            }
            else {
                Write-Output "$($MyInvocation.MyCommand): Importing dependency from $ModuleName"
                Import-Module $ModuleName
            }
        }
        elseif (Test-Path $ModuleFullLocalPath) {
            if ($ModuleExt -eq 'ps1') {
                Write-Output "$($MyInvocation.MyCommand): Dot sourcing dependency from $ModuleFullLocalPath"
                . $ModuleFullLocalPath
            }
            else {
                Write-Output "$($MyInvocation.MyCommand): Importing dependency from $ModuleFullLocalPath"
                Import-Module $ModuleFullLocalPath
            }
        }
        else {
            $depwebclient = New-Object System.Net.WebClient 
            try {
                $DownloadDest = $ScriptPath + '\' + ($DependentFiles[$ModuleName] -split '/' | Select -Last 1)
                Write-Output "$($MyInvocation.MyCommand): Downloading dependency from $($DependentFiles[$ModuleName]) to $DownloadDest"
                $depwebclient.DownloadFile($DependentFiles[$ModuleName], $DownloadDest) | Out-Null
                if ($ModuleFullLocalPath -ne $DownloadDest) {
                    if (($DownloadDest -split '\.' | select -Last 1) -eq 'zip') {
                        Write-Output "$($MyInvocation.MyCommand): Downloaded zip file $((Split-Path $DownloadDest -Leaf))"
                        $shell = new-object -com shell.application
                        $zip = $shell.NameSpace($DownloadDest)
                        foreach($item in ($zip.items() | Where {$_ -eq $ModuleFileName})) {
                            $shell.Namespace((Split-Path $DownloadDest -Parent)).copyhere($item)
                        }
                    }
                }
                Unblock-File $ModuleFullLocalPath -ErrorAction:SilentlyContinue
                if ($ModuleExt -eq 'ps1') {
                    Write-Output "$($MyInvocation.MyCommand): Dot sourcing dependency from $ModuleFullLocalPath"
                    . $ModuleFullLocalPath
                }
                else {
                    Write-Output "$($MyInvocation.MyCommand): Importing dependency from $ModuleFullLocalPath"
                    Import-Module $ModuleFullLocalPath
                }
            }
            catch {
                throw "$($MyInvocation.MyCommand): Unable to download dependency file - $ModuleFileName"
                $DependenciesLoaded = $false
            }
        }
    }
    else {
        Write-Output "$($MyInvocation.MyCommand): Module already loaded - $ModuleFileName"
    }
}

if (-not $DependenciesLoaded) {
    Write-Error "$($MyInvocation.MyCommand): Unable to load all required dependencies!"
    return
}
#endregion Dependancies

# The Convert-HexStringToByteArray and Convert-ByteArrayToString functions are from
# Link: http://www.sans.org/windows-security/2010/02/11/powershell-byte-array-hex-convert
function Convert-HexStringToByteArray {
    ################################################################
    #.Synopsis
    # Convert a string of hex data into a System.Byte[] array. An
    # array is always returned, even if it contains only one byte.
    #.Parameter String
    # A string containing hex data in any of a variety of formats,
    # including strings like the following, with or without extra
    # tabs, spaces, quotes or other non-hex characters:
    # 0x41,0x42,0x43,0x44
    # \x41\x42\x43\x44
    # 41-42-43-44
    # 41424344
    # The string can be piped into the function too.
    ################################################################
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [String] $String
    )
     
    #Clean out whitespaces and any other non-hex crud.
    #   Try to put into canonical colon-delimited format.
    #   Remove beginning and ending colons, and other detritus.
    $String = $String.ToLower() -replace '[^a-f0-9\\\,x\-\:]','' `
                                -replace '0x|\\x|\-|,',':' `
                                -replace '^:+|:+$|x|\\',''
     
    #Maybe there's nothing left over to convert...
    if ($String.Length -eq 0) { ,@() ; return } 
     
    #Split string with or without colon delimiters.
    if ($String.Length -eq 1) { 
        ,@([System.Convert]::ToByte($String,16))
    }
    elseif (($String.Length % 2 -eq 0) -and ($String.IndexOf(":") -eq -1)) { 
        ,@($String -split '([a-f0-9]{2})' | foreach-object {
            if ($_) {
                [System.Convert]::ToByte($_,16)
            }
        }) 
    }
    elseif ($String.IndexOf(":") -ne -1) { 
        ,@($String -split ':+' | foreach-object {[System.Convert]::ToByte($_,16)})
    }
    else { 
        ,@()
    }
    #The strange ",@(...)" syntax is needed to force the output into an
    #array even if there is only one element in the output (or none).
}
 
function Convert-ByteArrayToString {
    <#
    .Synopsis
    Returns the string representation of a System.Byte[] array. ASCII string is the default, but Unicode, UTF7, UTF8 and UTF32 are available too.
    .Parameter ByteArray
    System.Byte[] array of bytes to put into the file. If you pipe this array in, you must pipe the [Ref] to the array. Also accepts a single Byte object instead of Byte[].
    .Parameter Encoding
    Encoding of the string: ASCII, Unicode, UTF7, UTF8 or UTF32. ASCII is the default.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [System.Byte[]]$ByteArray,
        [Parameter()]
        [string]$Encoding = 'ASCII'
    )
     
    switch ( $Encoding.ToUpper() ) {
    	 "ASCII"   { $EncodingType = "System.Text.ASCIIEncoding" }
    	 "UNICODE" { $EncodingType = "System.Text.UnicodeEncoding" }
    	 "UTF7"    { $EncodingType = "System.Text.UTF7Encoding" }
    	 "UTF8"    { $EncodingType = "System.Text.UTF8Encoding" }
    	 "UTF32"   { $EncodingType = "System.Text.UTF32Encoding" }
    	 Default   { $EncodingType = "System.Text.ASCIIEncoding" }
    }
    $Encode = new-object $EncodingType
    $Encode.GetString($ByteArray)
}
 
function ConvertTo-MailboxIdentification {
    [CmdletBinding()] 
    param (
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [String] $EncodedString
    )
 
	$ByteArray   = Convert-HexStringToByteArray -String $EncodedString
	$ByteArray   = $ByteArray | Where-Object { ( ($_ -ge 32) -and ($_ -le 127) ) -or ($_ -eq 0) }
	$ByteString  = Convert-ByteArrayToString -ByteArray $ByteArray -Encoding ASCII
	$StringArray = $ByteString.Split([char][int](0))
	$StringArray[21]
}
 
function ConvertFrom-MailboxID {
    <#
    .SYNOPSIS
    Convert Encoded Mailbox ID to Email Address
     
    .PARAMETER MailboxID 
    The mailbox identification string as provided by the DMS System
     
    .DESCRIPTION
    Takes the encoded Mailbox ID from the DMS System and returns the email address of the end user.

    .EXAMPLE     
    PS C:\> ConvertFrom-MailboxID -MailboxID "0000000038A1BB1005E5101AA1BB08002B2A56C20000454D534D44422E444C4C00000000000000001B55FA20AA6611CD9BC800AA002FC45A0C00000053414E4445584D42583031002F4F3D50697065722026204D6172627572792F4F553D504D2F636E3D526563697069656E74732F636E3D616265636B737465616400"
     
    John.Zoidberg@planetexpress.com

    .NOTES
    Requires active connection to the Active Directory infrastructure
    #>
    [CmdletBinding()]
    param(
     	[Parameter(Position=0,Mandatory=$true)]
    	[string]$MailboxID
    )
    try {
        $MailboxDN = ConvertTo-MailboxIdentification -EncodedString $MailboxID 
        $ADSISearch = [DirectoryServices.DirectorySearcher]""
        $ADSISearch.Filter = "(&(&(&(objectCategory=user)(objectClass=user)(legacyExchangeDN=" + $MailboxDN + "))))"
        $SearchResults = $ADSISearch.FindOne()
        if ( -not $SearchResults ) {
            $ADSISearch.Filter = "(&(objectclass=user)(objectcategory=person)(proxyaddresses=x500:" + $MailboxDN + "))"
            $SearchResults = $ADSISearch.FindOne()    
        }
        $SearchResults.Properties.mail
    }
    catch {
        throw
    }
}
 
function ConvertFrom-FolderID {
    <#
    .SYNOPSIS
    Convert Encoded Folder ID to Folder Path
     
    .PARAMETER EmailAddress
    The email address of the mailbox in question.  Can also be used as the return
    value from ConvertFrom-MailboxID
     
    .PARAMETER FolderID
    The mailbox identification string as provided by the DMS System
     
    .PARAMETER ImpersonationCredential
    The credential to use when accessing Exchange Web Services.
     
    .DESCRIPTION
    Takes the encoded Folder ID from the DMS System and returns the folder path for
    the Folder ID with the user mailbox.
     
    .EXAMPLE
    PS C:\> ConvertFrom-FolderID -EmailAddress "hubert.farnsworth@planetexpress.com" -FolderID "0000000038A1BB1005E5101AA1BB08002B2A56C20000454D534D44422E444C4C00000000000000001B55FA20AA6611CD9BC800AA002FC45A0C00000053414E4445584D42583031002F4F3D50697065722026204D6172627572792F4F553D504D2F636E3D526563697069656E74732F636E3D616265636B737465616400" -ImpersonationCredential $EWSAdmin
     
    \Inbox\Omicron Persei 8\Lrrr

    .EXAMPLE 
    PS C:\> $EmailAddress = ConvertFrom-MailboxID -MailboxID "0000000038A1BB1005E5101AA1BB08002B2A56C20000454D534D44422E444C4C00000000000000001B55FA20AA6611CD9BC800AA002FC45A0C00000042414C5445584D42583033002F4F3D50697065722026204D6172627572792F4F553D504D2F636E3D526563697069656E74732F636E3D6162313836353600D83521F3C10000000100000014000000850000002F6F3D50697065722026204D6172627572792F6F753D45786368616E67652041646D696E6973747261746976652047726F7570202846594449424F484632335350444C54292F636E3D436F6E66696775726174696F6E2F636E3D536572766572732F636E3D42414C5445584D4258303300420041004C005400450058004D0042005800300033002E00500069007000650072002E0052006F006F0074002E004C006F00630061006C0000000000"
    PS C:\> ConvertFrom-FolderID -EmailAddress $EmailAddress -FolderID "0000000038A1BB1005E5101AA1BB08002B2A56C20000454D534D44422E444C4C00000000000000001B55FA20AA6611CD9BC800AA002FC45A0C00000053414E4445584D42583031002F4F3D50697065722026204D6172627572792F4F553D504D2F636E3D526563697069656E74732F636E3D616265636B737465616400" -ImpersonationCredential $EWSAdmin
     
    \Inbox\Amphibios 9\Kif Kroker
     
    .NOTES
    This function requires Exchange Web Services Managed API version 1.2.
    The EWS Managed API can be obtained from: http://www.microsoft.com/en-us/download/details.aspx?id=28952
    #>
    [CmdletBinding()]
    param(
    	[Parameter(Mandatory=$true)]
    	[object]$EWSService,
     	[Parameter(Mandatory=$true)]
    	[string]$EmailAddress,
        [Parameter(Mandatory=$true)]
    	[string]$FolderID,
    	[Parameter(Mandatory=$false)]
    	[ValidateSet("EwsLegacyId", "EwsId", "EntryId", "HexEntryId", "StoreId", "OwaId")]
    	[string]$InputFormat = "EwsId",
    	[Parameter(Mandatory=$false)]
    	[ValidateSet("FolderPath", "EwsLegacyId", "EwsId", "EntryId", "HexEntryId", "StoreId", "OwaId")]
    	[string]$OutputFormat = "FolderPath"
    )
	Write-Verbose "Converting $FolderID from $InputFormat to $OutputFormat"
 
    #region Build Alternative ID Object
    $AlternativeIdItem  = New-Object Microsoft.Exchange.WebServices.Data.AlternateId
	$AlternativeIdItem.Mailbox = $EmailAddress
	$AlternativeIdItem.UniqueId = $FolderID
	$AlternativeIdItem.Format = [Microsoft.Exchange.WebServices.Data.IdFormat]::$InputFormat
    #endregion Build Alternative ID Object
 
    #region Retrieve Folder Path from EWS
    try {
        if ( $OutputFormat -eq "FolderPath" ) {
			# Build the Folder Property Set and then add Properties that we want
			$psFolderPropertySet = New-Object -TypeName Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
 
			# Define the Folder Extended Property Set Elements
			$PR_Folder_Path = New-Object -TypeName Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(26293, [Microsoft.Exchange.WebServices.Data.MapiPropertyType]::String)
 
			# Add to the Folder Property Set Collection
			$psFolderPropertySet.Add($PR_Folder_Path)
 
			$EwsFolderID = $EWSService.ConvertId($AlternativeIdItem, [Microsoft.Exchange.WebServices.Data.IdFormat]::EwsId)
	        $EwsFolder = New-Object Microsoft.Exchange.WebServices.Data.FolderID($EwsFolderID.UniqueId)
	        $TargetFolder = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($EWSService, $EwsFolder, $psFolderPropertySet)
	        
            # Retrieve the first Property (Folder Path in a Raw State)
	        $FolderPathRAW = $TargetFolder.ExtendedProperties[0].Value
	        # The Folder Path attribute actually contains non-ascii characters in place of the backslashes
	        #   Since the first character is one of these non-ascii characters, we use that for the replace method
	        $ConvertedFolderId = $FolderPathRAW.Replace($FolderPathRAW[0], "\")
		}
		else {
			$EwsFolderID = $Service.ConvertId($AlternativeIdItem, [Microsoft.Exchange.WebServices.Data.IdFormat]::$OutputFormat )
			$ConvertedFolderId = $EwsFolderId.UniqueId
		}
    }
    catch {
        $ConvertedFolderId = $null
    }
    finally {
        $ConvertedFolderId
    }
    #endregion Retrieve Folder Path from EWS
}
 
function ConvertTo-HexId{    
	param (
	        $EWSid,
            $EmailAddress
		  )
	process{
	    $aiItem = New-Object Microsoft.Exchange.WebServices.Data.AlternateId      
	    $aiItem.Mailbox = $EmailAddress
	    $aiItem.UniqueId = $EWSid   
	    $aiItem.Format = [Microsoft.Exchange.WebServices.Data.IdFormat]::EWSId   
	    $convertedId = $service.ConvertId($aiItem, [Microsoft.Exchange.WebServices.Data.IdFormat]::HexEntryId) 
		return $convertedId.UniqueId
	}
}

function Load-EWS {
    <#
    .SYNOPSIS
    Load EWS dlls and create type accelerators for other functions.

    .DESCRIPTION
    Load EWS dlls and create type accelerators for other functions.
     
    .PARAMETER EWSManagedApiPath
    Full path to Microsoft.Exchange.WebServices.dll. If not provided we will try to load it from several best guess locations.
     
    .EXAMPLE
    Load-EWS
         
    .NOTES
    This function requires Exchange Web Services Managed API. From what I can tell you don't even need to install the msi. AS long
    as the Microsoft.Exchange.WebServices.dll file is extracted and available that should work.
    
    The EWS Managed API can be obtained from: http://www.microsoft.com/en-us/download/details.aspx?id=28952    
    #>
    [CmdletBinding()]
    param (
        [parameter(Position=0)]
        [string]$EWSManagedApiPath
    )
    if (-not (get-module Microsoft.Exchange.WebServices)) {
        if ($hostinvocation -ne $null) {
            $ScriptPath = Split-Path $hostinvocation.MyCommand.path
        }
        else {
            $ScriptPath = Split-Path $script:MyInvocation.MyCommand.Path
        }
        $EWSLoaded = $false
        if (-not [string]::IsNullOrEmpty($EWSManagedApiPath)) {
            try {
                Write-Verbose ('Load-EWS: Attempting to load {0}' -f $EWSManagedApiPath)
                Import-Module -Name $EWSManagedApiPath -ErrorAction Stop
                $EWSLoaded = $true
            }
            catch {
                Write-Warning ('Load-EWS: Cant load EWS module. Please verify this path - {0}' -f $EWSManagedApiPath)
                throw ('Load-EWS: Full Error - {0}' -f $_.Exception.Message)
            }
        }
        else {
            $ewspaths = @( "$ScriptPath\Microsoft.Exchange.WebServices.dll",
                           'C:\Program Files (x86)\Microsoft\Exchange\Web Services\2.1\Microsoft.Exchange.WebServices.dll',
                           'C:\Program Files\Microsoft\Exchange\Web Services\2.1\Microsoft.Exchange.WebServices.dll'
                         )
            foreach ($ewspath in $ewspaths) {
                try {
                    if (-not $EWSLoaded) {
                        if (Test-Path $ewspath) {
                            Write-Verbose ('Load-EWS: Attempting to load {0}' -f $ewspath)
                            Import-Module -Name $ewspath -ErrorAction:Stop
                            $EWSLoaded = $true
                        }
                    }
                }
                catch {}
            }
        }
    }
    else {
        $EWSLoaded = $true
    }
    if ($EWSLoaded) {
        $EWSAccels = @{
            'ews_basepropset' = 'Microsoft.Exchange.WebServices.Data.BasePropertySet'
            'ews_connidtype' = 'Microsoft.Exchange.WebServices.Data.ConnectingIdType'
            'ews_extendedpropset' = 'Microsoft.Exchange.WebServices.Data.DefaultExtendedPropertySet'
            'ews_extendedpropdef' = 'Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition'
            'ews_propset' = 'Microsoft.Exchange.WebServices.Data.PropertySet'
            'ews_folder' = 'Microsoft.Exchange.WebServices.Data.Folder'
            'ews_calendarfolder' = 'Microsoft.Exchange.WebServices.Data.CalendarFolder'
            'ews_calendarview' = 'Microsoft.Exchange.WebServices.Data.CalendarView'
            'ews_folderid' = 'Microsoft.Exchange.WebServices.Data.FolderId'
            'ews_folderview' = 'Microsoft.Exchange.WebServices.Data.FolderView'
            'ews_impersonateuserid' = 'Microsoft.Exchange.WebServices.Data.ImpersonatedUserId'
            'ews_mailbox' = 'Microsoft.Exchange.WebServices.Data.Mailbox'
            'ews_mapiproptype' = 'Microsoft.Exchange.WebServices.Data.MapiPropertyType'
            'ews_operator' = 'Microsoft.Exchange.WebServices.Data.LogicalOperator'
            'ews_resolvenamelocation' = 'Microsoft.Exchange.WebServices.Data.ResolveNameSearchLocation'
            'ews_schema_appt' = 'Microsoft.Exchange.WebServices.Data.AppointmentSchema'
            'ews_schema_folder' = 'Microsoft.Exchange.WebServices.Data.FolderSchema'
            'ews_schema_item' = 'Microsoft.Exchange.WebServices.Data.ItemSchema'
            'ews_searchfilter' = 'Microsoft.Exchange.WebServices.Data.SearchFilter'
            'ews_searchfilter_collection' = 'Microsoft.Exchange.WebServices.Data.SearchFilter+SearchFilterCollection'
            'ews_searchfilter_isequalto' = 'Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo'
            'ews_searchfilter_isgreaterthanorequalto' = 'Microsoft.Exchange.WebServices.Data.SearchFilter+IsGreaterThanOrEqualTo'
            'ews_searchfilter_islessthanorequalto' = 'Microsoft.Exchange.WebServices.Data.SearchFilter+IsLessThanOrEqualTo'
            'ews_searchfilter_exists' = 'Microsoft.Exchange.WebServices.Data.SearchFilter+Exists'
            'ews_service' = 'Microsoft.Exchange.WebServices.Data.ExchangeService'
            'ews_webcredential' = 'Microsoft.Exchange.WebServices.Data.WebCredentials'
            'ews_wellknownfolder' = 'Microsoft.Exchange.WebServices.Data.WellKnownFolderName'
            'ews_itemview' = 'Microsoft.Exchange.WebServices.Data.ItemView'
            'ews_appttype' = 'Microsoft.Exchange.WebServices.Data.AppointmentType'
            'ews_appt' = 'Microsoft.Exchange.WebServices.Data.Appointment'
        }
        # Setup a bunch of type accelerators to make this mess easier to understand (slightly)
        $accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')

        Add-Type -AssemblyName Microsoft.Exchange.WebServices
        foreach ($Key in $EWSAccels.Keys) {
            Write-Verbose "Load-EWS: Adding type accelerator - $Key for the type $($EWSAccels[$Key])"
            $accelerators::Add($Key,$EWSAccels[$Key])
        }
        return $true
    }
    else {
        throw 'Load-EWS: Cant load EWS module. Please verify it is installed or manually provide the path to Microsoft.Exchange.WebServices.dll'
    }
}

function Unload-EWS {
    [CmdletBinding()]
    param ()
    if (get-module Microsoft.Exchange.WebServices) {
        $accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
        $accelkeys = $accelerators::get
        $accelkeyscopy = @{}
        $accelkeys.Keys | Where {$_ -like 'ews_*'} | Foreach { $accelkeyscopy.$_ = $accelkeys[$_] }
        foreach ( $key in $accelkeyscopy.Keys ) {
            Write-Verbose "Unload-EWS: Removing type accelerator - $($key)"
            $accelerators::Remove("$($key)") | Out-Null
        }
        return $true
    }
    else {
        throw 'Load-EWS: Cant Unload EWS module as it was never loaded.'
    }
}

function Get-AutodiscoverEmailAddress {
    [CmdletBinding()]
    param(
        [parameter(Position=0, HelpMessage='ID to lookup. Defaults to current users SID')]
        [string]$UserID = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    )

    if (-not (Test-EmailAddressFormat $UserID)) {        
        try {
            if (Test-UserSIDFormat $UserID) {
                $user = [ADSI]"LDAP://<SID=$sid>"
                $retval = $user.Properties.mail
            }
            else {
                $strFilter = "(&(objectCategory=User)(samAccountName=$($UserID)))"
                $objSearcher = New-Object System.DirectoryServices.DirectorySearcher
                $objSearcher.Filter = $strFilter
                $objPath = $objSearcher.FindOne()
                $objUser = $objPath.GetDirectoryEntry()
                $retval = $objUser.mail
            }
        }
        catch {
            Write-Warning ('Get-AutodiscoverEmailAddress: Cannot get directory information for {0}' -f $UserID)
            Write-Debug ('Get-AutodiscoverEmailAddress: Full Error - {0}' -f $_.Exception.Message)
            throw 'Get-AutodiscoverEmailAddress: Autodiscover failure'
        }
        if ([string]::IsNullOrEmpty($retval)) {
            Write-Warning ('Connect-EWS: Cannot determine the primary email address for {0}' -f $UserID)
            throw 'Get-AutodiscoverEmailAddress: Autodiscover failure - No email address associated with current user.'
        }
        else {
            return $retval
        }
    }
    else {
        return $UserID
    }
}

function Connect-EWS {
    [CmdLetBinding(DefaultParameterSetName='Default')]
    param(
        [parameter(Mandatory=$True,ParameterSetName='CredentialString', HelpMessage='Alternate credential username.')]
        [string]$UserName,
        [parameter(Mandatory=$True,ParameterSetName='CredentialString')]
        [string]$Password,
        [parameter(ParameterSetName='CredentialString')]
        [string]$Domain,
        [parameter(Mandatory=$True,ParameterSetName='CredentialObject')]
        [System.Management.Automation.PSCredential]$Creds,
        [parameter(ParameterSetName='CredentialString')]
        [parameter(ParameterSetName='CredentialObject')]
        [parameter(ParameterSetName='Default')]
        [ValidateSet('Exchange2013_SP1','Exchange2013','Exchange2010_SP2','Exchange2010_SP1','Exchange2010','Exchange2007_SP1')]
        [string]$ExchangeVersion = 'Exchange2010_SP2',
        [parameter(ParameterSetName='CredentialString')]
        [parameter(ParameterSetName='CredentialObject', HelpMessage='Use statically set ews url. Autodiscover is attempted otherwise.')]
        [parameter(ParameterSetName='Default')]
        [string]$EwsUrl='',
        [parameter(ParameterSetName='CredentialString')]
        [parameter(ParameterSetName='CredentialObject')]
        [parameter(ParameterSetName='Default')]
        [switch]$EWSTracing,
        [parameter(ParameterSetName='CredentialString')]
        [parameter(ParameterSetName='CredentialObject')]
        [parameter(ParameterSetName='Default')]
        [switch]$IgnoreSSLCertificate
    )
    #Load saved credential file if specified
    switch ($PSCmdlet.ParameterSetName) {
        'CredentialObject' {
            $UserName= $Creds.GetNetworkCredential().UserName
            $Password = $Creds.GetNetworkCredential().Password
            $Domain = $Creds.GetNetworkCredential().Domain
        }
    }

    if ($IgnoreSSLCertificate) {
        Write-Verbose 'Connect-EWS: Ignoring any SSL certificate errors'
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    }

    try {        
        Write-Verbose 'Connect-EWS: Creating EWS Service object'
        $enumExchVer = [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::$ExchangeVersion
        $EWSService = new-object ews_service($enumExchVer) -ErrorAction Stop
    }
    catch {
        Write-Error ('Connect-EWS: Cannot create EWS Service with the following defined Exchange version- {0}' -f $ExchangeVersion)
        throw ('Connect-EWS: Full Error - {0}' -f $_.Exception.Message)
    }
    
    # If an alternate credential has been passed setup accordingly
    if ($UserName) {
        if ($Domain) {
            #If a domain is presented then use that as well
            $EWSService.Credentials = New-Object ews_webcredential($UserName,$Password,$Domain) -ErrorAction Stop
        }
        else {
            #Otherwise leave the domain blank
            $EWSService.Credentials = New-Object ews_webcredential($UserName,$Password) -ErrorAction Stop
        }
    }

    # Otherwise try to use the current account
    else {
        $EWSService.UseDefaultCredentials = $true
    }
    
    if ($EWSTracing) {
        Write-Verbose 'Connect-EWS: EWS Tracing enabled'
        $EWSservice.traceenabled = $true
    }

    # If an ews url was defined then use that first
    if (-not [string]::IsNullOrEmpty($EwsUrl)) {
        Write-Verbose 'Connect-EWS: Using the specifed EWS URL of $EwsUrl'
        $EWSService.URL = New-Object Uri($EwsUrl) -ErrorAction Stop
    }
    # Otherwise try to use autodiscover to get the url
    else {
        $AutoDiscoverSplat = @{}
        if ($UserID) {
            # If using an alternate userid then try autodiscover with it, otherwise the current account is used
            $AutoDiscoverSplat.UserID = $UserID
        }
        try {
            $AutodiscoverAccount = Get-AutodiscoverEmailAddress @AutoDiscoverSplat
        }
        catch {
            throw 'Connect-EWS: Unable to find a primary smtp account with this account!'
        }
        try {
            Write-Verbose ('Connect-EWS: Performing autodiscover for - {0}' -f $AutodiscoverAccount)
            $EWSService.AutodiscoverUrl($AutodiscoverAccount)
        }
        catch {
            Write-Error ('Connect-EWS: EWS Url not specified and autodiscover failed')
            throw ('Connect-EWS: Full Error - {0}' -f $_.Exception.Message)
        }
    }
    return $EWSService
}

function Impersonate-EWSMailbox {
    [CmdletBinding()]
    param(
        [parameter(Position=0, Mandatory=$True, HelpMessage='Connected EWS object.')]
        [object]$EWSService,
        [parameter(Position=1, Mandatory=$True, HelpMessage='Mailbox to impersonate.')]
        [string]$Mailbox,
        [parameter(Position=2, HelpMessage='Do not attempt to validate rights against this mailbox (can speed up operations)')]
        [switch]$SkipValidation
    )
    if (Test-EmailAddressFormat $Mailbox) {
        $enumType = [ews_connidtype]::SmtpAddress
    }
    else {
        $enumType = [ews_connidtype]::PrincipalName
    }
    try {
        $EWSService.ImpersonatedUserId = New-Object ews_impersonateuserid($enumType,$Mailbox)
        if (-not $SkipValidation) {
            $InboxFolder= new-object ews_folderid([ews_wellknownfolder]::Inbox,$Mailbox)
            $Inbox = [ews_folder]::Bind($EWSService,$InboxFolder)
        }
    }
    catch {
        Write-Error ('Impersonate-EWSMailbox: Unable to impersonate {0}, check to see that you have adequately assigned permissions to impersonate this account.' -f $Mailbox)
        throw $_.Exception.Message  
    }
}

function Get-EWSFolder {
    [CmdletBinding()]
    param(
        [parameter(Position=0, Mandatory=$True, HelpMessage='Connected EWS object.')]
        [object]$EWSService,
        [parameter(Position=1, HelpMessage='Mailbox of folder.')]
        [string]$Mailbox,
        [parameter(Position=2, HelpMessage='Folder to convert.')]
        [string]$FolderPath,
        [parameter(Position=2, HelpMessage='Public Folder Path?')]
        [switch]$PublicFolder
    )
    
    # Return a reference to a folder specified by path 
    if ($PublicFolders) { 
        $mbx = '' 
        $Folder = [ews_folder]::Bind($EWSService, [ews_wellknownfolder]::PublicFoldersRoot) 
    } 
    else {
        $mbx = New-Object ews_mailbox( $Mailbox ) 
        $folderId = New-Object ews_folderid([ews_wellknownfolder]::MsgFolderRoot, $mbx ) 
        $Folder = [ews_folder]::Bind($EWSService, $folderId) 
    } 
 
    if ($FolderPath -ne '\') {
        $PathElements = $FolderPath -split '\\' 
        For ($i=0; $i -lt $PathElements.Count; $i++) { 
            if ($PathElements[$i]) { 
                $View = New-Object  ews_folderview(2,0) 
                $View.PropertySet = [ews_basepropset]::IdOnly
                $SearchFilter = New-Object ews_searchfilter_isequalto([ews_schema_folder]::DisplayName, $PathElements[$i])
                $FolderResults = $Folder.FindFolders($SearchFilter, $View) 
                if ($FolderResults.TotalCount -ne 1) { 
                    # We have either none or more than one folder returned... Either way, we can't continue 
                    $Folder = $null 
                    Write-Host "Failed to find $($PathElements[$i]), path requested was $FolderPath" -ForegroundColor Red 
                    break 
                }
                 
                if (-not [String]::IsNullOrEmpty(($mbx))) {
                    $folderId = New-Object ews_folderid($FolderResults.Folders[0].Id, $mbx ) 
                    $Folder = [ews_folder]::Bind($service, $folderId) 
                } 
                else {
                    $Folder = [ews_folder]::Bind($service, $FolderResults.Folders[0].Id) 
                } 
            } 
        } 
    } 

    return $Folder 
}

function Get-EWSTargettedMailbox {
    # Supplemental function 
    [CmdletBinding()]
    param(
        [parameter(Position=0, Mandatory=$True, HelpMessage='Connected EWS object.')]
        [object]$EWSService,
        [parameter(Position=1, HelpMessage='Mailbox of folder.')]
        [string]$Mailbox
    )
    if (-not [string]::IsNullOrEmpty($Mailbox)) {
        if (Test-EmailAddressFormat $Mailbox) {
            $email = $Mailbox
        }
        else {
            try {
                $email = Get-AutodiscoverEmailAddress $Mailbox
            }
            catch {
                throw 'Get-EWSTargettedMailbox: Unable to get a mailbox'
            }
        }
    }
    else {
        if ($EWSService.ImpersonatedUserId -ne $null) {
            $impID = $EWSService.ImpersonatedUserId.Id
        }
        else {
            $impID = $EWSService.Credentials.Credentials.UserName
        }
        
        if (-not (Test-EmailAddressFormat $impID)) {
            try {
                $email = ($EWSService.ResolveName("smtp:$($ImpID)@",[ews_resolvenamelocation]::DirectoryOnly, $false)).Mailbox   -creplace '(?s)^.*\:', '' -creplace '>',''
            }
            catch {
                throw 'Get-EWSTargettedMailbox: Unable to find a mailbox with this account.'
            }
        }
        else {
            $email = $impID
        }
    }
    
    return $email
}

function Get-EWSCalenderViewAppointments {
    # uses a slower method for accessing appointments
    [CmdletBinding()]
    param(
        [parameter(Position=0, Mandatory=$True, HelpMessage='Connected EWS object.')]
        [object]$EWSService,
        [string]$Mailbox = '',
        [datetime]$StartRange = (Get-Date),
        [datetime]$EndRange = ((Get-Date).AddMonths(12))
    )
    
    $email = Get-EWSTargettedMailbox -EWSService $EWSService -Mailbox $Mailbox
    
    Write-Verbose "Get-EWSCalendarEnties: Attempting to gather calendar entries for $($email)"
    $MailboxToAccess = new-object ews_mailbox($email)

    $FolderID = new-object ews_folderid([ews_wellknownfolder]::Calendar, $MailboxToAccess)

    $EWSCalFolder = [ews_calendarfolder]::Bind($EWSService, $FolderID)
    $propsetfc = [ews_basepropset]::FirstClassProperties
    $Calview = new-object ews_calendarview($StartRange, $EndRange, 1000)
    $Calview.PropertySet = $propsetfc

    $appointments = @()
    $CalSearchResult = $EWSService.FindAppointments($EWSCalFolder.id, $Calview)
    $appointments += $CalSearchResult

    while($CalSearchResult.MoreAvailable) {
        $calview.StartDate = $CalSearchResult.Items[$CalSearchResult.Items.Count-1].Start
        $CalSearchResult = $EWSService.FindAppointments($EWSCalFolder.id, $Calview)
        $appointments += $CalSearchResult
    }

    $appointments.GetEnumerator()
}

function Get-EWSCalendarAppointments {
    # Use FindItems as opposed to FindAppointments
    [CmdletBinding()]
    param(
        [parameter(Position=0, Mandatory=$True, HelpMessage='Connected EWS object.')]
        [ValidateNotNullOrEmpty()]
        [object]$EWSService,
        [Parameter(HelpMessage="Mailbox to search - if omitted the EWS connection account ID is used (or impersonated account if set).")] 
        [string]$Mailbox = '',
        [Parameter(HelpMessage="Folder to search - if omitted, the mailbox calendar folder is assumed")] 
        $FolderPath,
        [Parameter(HelpMessage="Subject of the appointment(s) being searched")] 
        [string]$Subject,
        [Parameter(HelpMessage="Start date for the appointment(s) must be after this date")] 
        [datetime]$StartsAfter,
        [Parameter(HelpMessage="Start date for the appointment(s) must be before this date")] 
        [datetime]$StartsBefore, 
        [Parameter(HelpMessage="End date for the appointment(s) must be after this date")] 
        [datetime]$EndsAfter, 
        [Parameter(HelpMessage="End date for the appointment(s) must be before this date")] 
        [datetime]$EndsBefore, 
        [Parameter(HelpMessage="Only appointments created before the given date will be returned")] 
        [datetime]$CreatedBefore, 
        [Parameter(HelpMessage="Only appointments created after the given date will be returned")] 
        [datetime]$CreatedAfter, 
        [Parameter(HelpMessage="Only recurring appointments with a last occurrence date before the given date will be returned")] 
        [datetime]$LastOccurrenceBefore, 
        [Parameter(HelpMessage="Only recurring appointments with a last occurrence date after the given date will be returned")] 
        [datetime]$LastOccurrenceAfter, 
        [Parameter(HelpMessage="If this switch is present, only recurring appointments are returned")]
        [switch]$IsRecurring,
        [Parameter(HelpMessage='Search for extended properties being set.')]
        [ews_extendedpropdef[]]$ExtendedProperties
    )
    
    $email = Get-EWSTargettedMailbox -EWSService $EWSService -Mailbox $Mailbox

    Write-Verbose "Get-EWSCalendarEnties: Attempting to gather calendar entries for $($email)"

    $MailboxToAccess = new-object ews_mailbox($email)

    if ([string]::IsNullOrEmpty($FolderPath)) {
        $FolderID = new-object ews_folderid([ews_wellknownfolder]::Calendar, $MailboxToAccess)
    }

    $EWSCalFolder = [ews_calendarfolder]::Bind($EWSService, $FolderID)
    $view = New-Object ews_itemview(500, 0)
    
    $offset = 0 
    $moreItems = $true
    $filters = @()
    
	#region Build Extended Property Set for Item Results
	# Build the Item Property Set and then add the Properties that we want
	$customPropSet = New-Object -TypeName ews_propset([ews_basepropset]::FirstClassProperties)

	# Define the Item Extended Properties and add to collection (if defined)
    if ($ExtendedProperties -ne $null) {
        $ExtendedProperties | Foreach {
            $customPropSet.Add($_)
            $filters += New-Object ews_searchfilter_exists($_)
        }
    }
    $customPropSet.Add([ews_schema_item]::ID)
    $customPropSet.Add([ews_schema_item]::Subject)
    $customPropSet.Add([ews_schema_appt]::Start)
    $customPropSet.Add([ews_schema_appt]::End)
    $customPropSet.Add([ews_schema_item]::DateTimeCreated)
    $customPropSet.Add([ews_schema_appt]::AppointmentType)
    $view.PropertySet = $customPropSet
    #endregion Build Extended Property Set for Item Results

    # Set the search filter - this limits some of the results, not all the options can be filtered 
    if ($createdBefore -ne $Null) { 
        $filters += New-Object ews_searchfilter_IsLessThanOrEqualTo([ews_schema_item]::DateTimeCreated, $CreatedBefore) 
    }
    if (-not [string]::IsNullOrEmpty($Subject)) { 
        $filters += New-Object ews_searchfilter_isequalto([ews_schema_item]::Subject, $Subject) 
    }
    if ($createdAfter -ne $Null) { 
        $filters += New-Object ews_searchfilter_IsGreaterThanOrEqualTo([ews_schema_item]::DateTimeCreated, $createdBefore) 
    } 
    if ($startsBefore -ne $Null) { 
        $filters += New-Object ews_searchfilter_IsLessThanOrEqualTo([ews_schema_appt]::Start, $startsBefore) 
    } 
    if ($startsAfter -ne $Null) { 
        $filters += New-Object ews_searchfilter_IsGreaterThanOrEqualTo([ews_schema_appt]::Start, $startsAfter) 
    } 
    if ($endsBefore -ne $Null) { 
        $filters += New-Object ews_searchfilter_IsLessThanOrEqualTo([ews_schema_appt]::End, $endsBefore) 
    } 
    if ($endsAfter -ne $Null) { 
        $filters += New-Object ews_searchfilter_IsGreaterThanOrEqualTo([ews_schema_appt]::End, $endsAfter) 
    }
    if ($IsRecurring) {
        $filters += New-Object ews_searchfilter_isequalto([ews_schema_appt]::IsRecurring,$true)
    }
    $searchFilter = $Null
    if ( $filters.Count -gt 0 ) { 
        $searchFilter = New-Object ews_searchfilter_collection([ews_operator]::And) 
        foreach ($filter in $filters) {
            $searchFilter.Add($filter) 
        } 
    } 
 
    # Now retrieve the matching items and process 
    while ($moreItems) { 
        # Get the next batch of items to process 
        if ( $searchFilter ) { 
            $results = $EWSCalFolder.FindItems($searchFilter, $view) 
        } 
        else { 
            $results = $EWSCalFolder.FindItems($view) 
        } 
        $moreItems = $results.MoreAvailable 
        $view.Offset = $results.NextPageOffset 

        $results
    }
}

function Create-EWSCalendarEntry {
    # Returns an appointment to be manipulated or saved later
    [CmdletBinding()]
    param(
        [parameter(Position=0, HelpMessage='Connected EWS object.')]
        [object]$EWSService,
        [parameter(HelpMessage = 'Free/busy status.')]
        [ValidateNotNullOrEmpty()]
        [Microsoft.Exchange.WebServices.Data.LegacyFreeBusyStatus[]]$FreeBusyStatus = [System.Enum]::GetValues([Microsoft.Exchange.WebServices.Data.LegacyFreeBusyStatus]),
        [bool]$IsAllDayEvent = $true,
        [datetime]$Start = (Get-Date),
        [datetime]$End = (Get-Date),
        [string]$Subject,
        [string]$Location,
        [string]$Body
    )

    Write-Verbose "Create-EWSCalendarEntry: Attempting to create an appointment"
    
    if ($FreeBusyStatus.count -gt 1) {
        $FreeBusyStatus = [Microsoft.Exchange.WebServices.Data.LegacyFreeBusyStatus]::Free
    }
    # Construct Appointment
    $appt = [ews_appt]($EWSService)
    $appt.StartTimeZone = $EWSService.TimeZone
    $appt.EndTimeZone   = $EWSService.TimeZone
    $appt.LegacyFreeBusyStatus = $FreeBusyStatus
    $appt.IsAllDayEvent = $IsAllDayEvent
    $appt.Start = $Start
    $appt.End = $End
    $appt.Subject = $Subject
    $appt.Location = $Location
    $appt.Body = $Body

    return $appt
}

function New-EWSExtendedProperty {
    [CmdletBinding()]
    param(
        [parameter(Position=0, HelpMessage='Type of extended property to create.')]
        [ValidateNotNullOrEmpty()]
        [Microsoft.Exchange.WebServices.Data.MapiPropertyType[]]$PropertyType = [System.Enum]::GetValues([Microsoft.Exchange.WebServices.Data.MapiPropertyType]),
        [parameter(Position=1, Mandatory=$True, HelpMessage='Name of extended property')]
        [ValidateNotNullOrEmpty()]
        [string]$PropertyName
    )
    if ($PropertyType.Count -gt 1) {
        $PropertyType = [ews_mapiproptype]::String
    }
    Write-Verbose "New-EWSExtendedProperty: Attempting to create an extended property"
    return New-Object -TypeName ews_extendedpropdef([ews_extendedpropset]::PublicStrings, $PropertyName, $PropertyType)
}