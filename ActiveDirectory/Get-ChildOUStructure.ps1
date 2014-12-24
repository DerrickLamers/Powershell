function Get-ChildOUStructure {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, ValueFromPipeline=$true, Mandatory=$true, HelpMessage='Array of OUs in CanonicalName formate (ie. domain/ou1/ou2)')]
        [string[]]$ouarray,
        [Parameter(Position=1, HelpMessage='Base of OU.')]
        [string]$oubase = ''
    )
    begin {
        $newarray = @()
        $base = ''
        $firstset = $false
        $ouarraylist = @()
    }
    process {
        $ouarraylist += $ouarray
    }
    end {
        $ouarraylist = $ouarraylist | Where {($_ -ne $null) -and ($_ -ne '')} | Select -Unique | Sort-Object
        if ($ouarraylist.count -gt 0) {
            $ouarraylist | Foreach {
               # $prioroupath = if ($oubase -ne '') {$oubase + '/' + $_} else {''}
                $firstelement = @($_ -split '/')[0]
                $regex = "`^`($firstelement`?`)"
                $tmp = $_ -replace $regex,'' -replace "^(\/?)",''

                if (-not $firstset) {
                    $base = $firstelement
                    $firstset = $true
                }
                else {
                    if (($base -ne $firstelement) -or ($tmp -eq '')) {
                        Write-Verbose "Processing Subtree for: $base"
                        $fulloupath = if ($oubase -ne '') {$oubase + '/' + $base} else {$base}
                        New-Object psobject -Property @{
                            'name' = $base
                            'path' = $fulloupath
                            'children' = if ($newarray.Count -gt 0) {,@(Get-ChildOUStructure -ouarray $newarray -oubase $fulloupath)} else {$null}
                        }
                        $base = $firstelement
                        $newarray = @()
                        $firstset = $false
                    }
                }
                if ($tmp -ne '') {
                    $newarray += $tmp
                }
            }
            Write-Verbose "Processing Subtree for: $base"
            $fulloupath = if ($oubase -ne '') {$oubase + '/' + $base} else {$base}
            New-Object psobject -Property @{
                'name' = $base
                'path' = $fulloupath
                'children' = if ($newarray.Count -gt 0) {,@(Get-ChildOUStructure -ouarray $newarray -oubase $fulloupath)} else {$null}
            }
        }
    }
}
$test = $OUs | Get-ChildOUStructure | ConvertTo-Json -Depth 20 | clip

# Example: 
#$OUs = @(Get-ADObject -Filter {(ObjectClass -eq "OrganizationalUnit")} -Properties CanonicalName).CanonicalName
#$test = $OUs | Get-ChildOUStructure | ConvertTo-Json -Depth 20
#$test -replace '  null','  [{}]'