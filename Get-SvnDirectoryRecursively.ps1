# helper functions 
function Split-Url {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$url
    )

    $LastSegment = $url.Segments[-1]
    $Parent = $url.AbsoluteUri.Replace($LastSegment, "")
    $HostUrl = $url.Scheme + "://" + $url.Authority

    $Segments = [System.Collections.ArrayList]$url.Segments
    $Segments.Insert(0, $HostUrl)   

    return [PSCustomObject]@{
        Url = $url
        Parent = $Parent
        Leaf = $LastSegment
        Segments = $Segments
        Authority = $url.Authority
    }
}

# stolen with good conscience under the MIT license
# https://www.powershellgallery.com/packages/Scrubber/0.1.0/Content/Private%5CJoin-Url.ps1
# https://github.com/Skatterbrainz/Scrubber/blob/master/LICENSE
function Join-Url {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$True, HelpMessage="Base Path")]
        [ValidateNotNullOrEmpty()]
        [string] $Path,
        [parameter(Mandatory=$True, HelpMessage="Child Path or Item Name")]
        [ValidateNotNullOrEmpty()]
        [string] $ChildPath
    )
    if ($Path.EndsWith('/')) {
        return "$Path"+"$ChildPath"
    }
    else {
        return "$Path/$ChildPath"
    }
}

function Get-SvnDirectoryRecursively {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$url,

        # default using whatever dir and creating output folder
        # if specified, it needs to be a full and valid drive path
        [Parameter(Mandatory = $false)]
        [string]$outputFolder = '.\output',

        # not needed i think
        [Parameter(Mandatory = $false)]
        [int]$depth = 0 
    )

    Write-Verbose $url

    # check if $outputFolder contains a drive name and a colon
    # this is hacky and won't support fileshares correctly, lol.
    if (-not ($outputFolder -like ("*:*"))) {
        Write-Verbose "joining paths"
        $outputFolder = Join-Path -Path $PSScriptRoot -ChildPath $outputFolder
        Write-Verbose "joined: $outputFolder"
    }

    if (-not (Test-Path -Path $outputFolder)) {
        [string]$outputFolder = New-Item -Path $outputFolder -ItemType Directory
        Write-Verbose "created directory: $outputFolder"
    }
    else {
        [string]$outputFolder = Get-Item -Path $outputFolder
        Write-Verbose "found directory: $outputFolder"
    }

    # this makes life a little easier
    $urlObject = Split-Url -url $url

    Write-Verbose $outputFolder
    Write-Verbose ($urlObject | Out-String)

    $currentWebDir = $urlObject.Url
    $currentWebDirParent = $urlObject.Parent

    Write-Verbose "Curr web dir: $currentwebDir"
    Write-Verbose "Curr web dir parent: $currentwebDirParent"
    
    #do a webrequest to the url and save the response to a variable
    $response = Invoke-WebRequest -Uri $url
    [System.Collections.ArrayList]$links = $response.Links 

    if ($links.Count -eq 0) {
        Write-Verbose "no links found"
        return
    }

    # we DO NOT navigate upwards in the structure
    $upLinks = @('../', './', '..', $currentWebDirParent)

    if ($upLinks -contains $links[0].href) {
        Write-Verbose "remove updir: $($links[0].href)"
        $links.RemoveAt(0)
    }

    # just in case an svn repo has removed the link to project
    if ($links[$links.Count - 1].href -like "*apache*") {
        Write-Verbose "remove link to apache $($links[$links.Count - 1].href)"
        $links.RemoveAt($links.Count - 1)
    }

    # files to download
    $fileContainer = [System.Collections.ArrayList]@() 

    # loop through each link and call the function again with the link as the url
    foreach ($link in $links) {

        $outputItemName = Join-Path -Path $outputFolder -ChildPath $urlObject.Leaf
        $fullUri = Join-Url -Path $currentWebDir -ChildPath $link.href 

        # meaning it's a file, not directory
        # we create the directory structure first
        # then download the file at the end
        if (-not ([string]$link.href).EndsWith('/')) {

            $fileObj = [PSCustomObject]@{
                href = $link.href
                parentPath = $outputFolder
                filePath = $outputItemName
                leaf = $urlObject.Leaf
                fullUri = $fullUri
            }
            $fileContainer.Add($fileObj)

            Write-Verbose "file: $($fileobj | Out-String)"
            continue
        }

        # this way we're ensuring the folder structure is 
        # copied exactly and then just ram the files innit
        if (-not (Test-Path -Path $outputItemName)) {
            New-Item -Path $outputItemName -ItemType Directory | Out-Null
            Write-Verbose "created directory: $outputItemName"
            continue
        }

        Write-Verbose "next function call `r`n : $fullUri `r`n outputItemName"

        # we keep digging deeper into the structure
        # using new values for the url and output folder
        Get-SvnDirectoryRecursively -url $fullUri -outputFolder $outputItemName -Verbose
    }

    Write-Verbose "files to download: $($fileContainer.Count)"

    # invoke webrequest and save to file under the directory it was found in
    foreach ($file in $fileContainer) {

        Write-Verbose "attempting dl: $($file.filePath)"
        Write-Verbose "fullUri: $($file.fullUri)"
        $fileResponse = Invoke-WebRequest -Uri $file.fullUri -outFile $file.filePath -ErrorAction Stop

        if ($fileResponse.StatusCode -eq 200) {
            Write-Verbose "downloaded file: $($file.filePath)"
        }
        else {
            Write-Verbose "failed to download file: $($file.filePath)"
        }
    }
}

Get-SvnDirectoryRecursively -url 'https://gtsvn.uit.no/freecorpus/orig/nob/' -Verbose
