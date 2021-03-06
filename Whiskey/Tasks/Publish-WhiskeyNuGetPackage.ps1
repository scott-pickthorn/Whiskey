
function Publish-WhiskeyNuGetPackage
{
    <#
    .SYNOPSIS
    Creates a NuGet package from .NET .csproj files.

    .DESCRIPTION
    The `Invoke-WhiskeyNuGetPackTask` runs `nuget.exe` against a list of .csproj files, which create a .nupkg file from that project's build output. The package can be uploaded to NuGet, ProGet, or other package management repository that supports NuGet.

    You must supply the path to the .csproj files to pack with the `$TaskParameter.Path` parameter, the directory where the packaged .nupkg files go with the `$Context.OutputDirectory` parameter, and the version being packaged with the `$Context.Version` parameter.

    You *must* include paths to build with the `Path` parameter.

    .EXAMPLE
    Invoke-WhiskeyNuGetPackageTask -Context $TaskContext -TaskParameter $TaskParameter

    Demonstrates how to package the assembly built by `TaskParameter.Path` into a .nupkg file in the `$Context.OutputDirectory` directory. It will generate a package at version `$Context.ReleaseVersion`.
    #>
    [Whiskey.Task("PublishNuGetLibrary")]
    [Whiskey.Task("PublishNuGetPackage")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    if( $TaskContext.TaskName -eq 'PublishNuGetLibrary' )
    {
        Write-Warning -Message ('We have renamed the ''PublishNuGetLibrary'' task to ''PublishNuGetPackage''. Please rename the task in ''{0}''. In a future version of Whiskey, the `PublishNuGetLibrary` name will no longer work.' -f $TaskContext.ConfigurationPath)
    }

    if( -not ($TaskParameter.ContainsKey('Path')))
    {
        $TaskParameter['Path'] = '.output\*.nupkg'
    }

    $publishSymbols = $TaskParameter['Symbols']

    $paths = $TaskParameter['Path'] | 
                Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path' | 
                Where-Object { 
                    $wildcard = '*.symbols.nupkg' 
                    if( $publishSymbols )
                    {
                        $_ -like $wildcard
                    }
                    else
                    {
                        $_ -notlike $wildcard
                    }
                }
       
    $source = $TaskParameter['Uri']
    if( -not $source )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''Uri'' is mandatory. It should be the URI where NuGet packages should be published, e.g. 
            
    BuildTasks:
    - PublishNuGetPackage:
        Uri: https://nuget.org
    ')
    }

    $apiKeyID = $TaskParameter['ApiKeyID']
    if( -not $apiKeyID )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''ApiKeyID'' is mandatory. It should be the ID/name of the API key to use when publishing NuGet packages to {0}, e.g.:
            
    BuildTasks:
    - PublishNuGetPackage:
        Uri: {0}
        ApiKeyID: API_KEY_ID
             
Use the `Add-WhiskeyApiKey` function to add the API key to the build.

            ' -f $source)
    }
    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $apiKeyID -PropertyName 'ApiKeyID'

    $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve
    if( -not $nugetPath )
    {
        return
    }

    foreach ($path in $paths)
    {
        $projectName = [IO.Path]::GetFileNameWithoutExtension(($path | Split-Path -Leaf))
        $projectName = $projectName -replace '\.\d+\.\d+\.\d+(-.*)?(\.symbols)?',''
        $packageVersion = $TaskContext.Version.SemVer1
        $packageUri = '{0}/package/{1}/{2}' -f $source,$projectName,$packageVersion
            
        # Make sure this version doesn't exist.
        $packageExists = $false
        $numErrorsAtStart = $Global:Error.Count
        try
        {
            Invoke-WebRequest -Uri $packageUri -UseBasicParsing | Out-Null
            $packageExists = $true
        }
        catch [Net.WebException]
        {
            if( ([Net.HttpWebResponse]([Net.WebException]$_.Exception).Response).StatusCode -ne [Net.HttpStatusCode]::NotFound )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Failure checking if {0} {1} package already exists at {2}. The web request returned a {3} status code.' -f $projectName,$packageVersion,$packageUri,$_.Exception.Response.StatusCode)
            }

            for( $idx = 0; $idx -lt ($Global:Error.Count - $numErrorsAtStart); ++$idx )
            {
                $Global:Error.RemoveAt(0)
            }
        }

        if( $packageExists )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('{0} {1} already exists. Please increment your library''s version number in ''{2}''.' -f $projectName,$packageVersion,$TaskContext.ConfigurationPath)
        }

        # Publish package and symbols to NuGet
        Invoke-WhiskeyNuGetPush -Path $path -Uri $source -ApiKey $apiKey
            
        try
        {
            Invoke-WebRequest -Uri $packageUri -UseBasicParsing | Out-Null
        }
        catch [Net.WebException]
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Failed to publish NuGet package {0} {1} to {2}. When we checked if that package existed, we got a {3} HTTP status code. Please see build output for more information.' -f $projectName,$packageVersion,$packageUri,$_.Exception.Response.StatusCode)
        }
    }
} 
