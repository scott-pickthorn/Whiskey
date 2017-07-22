
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$defaultPackageName = 'WhiskeyTest'
$defaultDescription = 'A package created to test the Invoke-WhiskeyProGetUniversalPackageTask function in the Whiskey module.'
$defaultVersion = '1.2.3'

$threwException = $false

$preTempDirCount = 0
$postTempDirCount = 0
function ThenTaskFails 
{
    Param(
        [String]
        $error
    )

        It ('should fail with error message that matches ''{0}''' -f $error) {
            $Global:Error | Should match $error
        }
}
function ThenTaskSucceeds 
{
        It ('should not throw an error message') {
            $Global:Error | Should BeNullOrEmpty
        }
}
function Assert-NewWhiskeyProGetUniversalPackage
{
    [CmdletBinding()]
    param(
        [object[]]
        $ForPath,

        [string[]]
        $ThatIncludes,

        [string[]]
        $ThatExcludes,

        [string]
        $Name = $defaultPackageName,

        [string]
        $ForApplicationName,

        [string]
        $Description = $defaultDescription,

        [string]
        $Version,

        [string[]]
        $HasRootItems,

        [string[]]
        $HasFiles,

        [string[]]
        $NotHasFiles,

        [string]
        $ShouldFailWithErrorMessage,
        
        [Switch]
        $ShouldNotCreatePackage,
        
        [Switch]
        $ShouldWriteNoErrors,

        [Switch]
        $ShouldReturnNothing,

        [string[]]
        $HasThirdPartyRootItem,

        [object[]]
        $WithThirdPartyRootItem,

        [string[]]
        $HasThirdPartyFile,

        [string]
        $FromSourceRoot,

        [string[]]
        $MissingRootItems,

        [Parameter(Mandatory=$true,ParameterSetName='ByDeveloper')]
        [Switch]
        $WhenRunByDeveloper,

        [Parameter(Mandatory=$true,ParameterSetName='ByBuildServer')]
        [Switch]
        $WhenRunByBuildServer,

        [Switch]
        $WhenCleaning
    )

    if( -not $Version )
    {
        $now = [DateTime]::Now
        $midnight = [DateTime]::Today

        $Version = '{0}.{1}.{2}-final+80.feature-fubarsnafu.deadbee' -f $now.Year,$now.DayOfYear,($now - $midnight).TotalMilliseconds.ToInt32($null)
        Start-Sleep -Milliseconds 1
    }

    $taskParameter = @{
                            Name = $Name;
                            Description = $Description;
                            Path = $ForPath;
                            Include = $ThatIncludes;
                        }
    if( $ThatExcludes )
    {
        $taskParameter['Exclude'] = $ThatExcludes
    }
    if( $HasThirdPartyRootItem )
    {
        $taskParameter['ThirdPartyPath'] = $WithThirdPartyRootItem
    }
    if( $FromSourceRoot )
    {
        $taskParameter['SourceRoot'] = $FromSourceRoot
    }

    $byWhoArg = @{ $PSCmdlet.ParameterSetName = $true }

    Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return $Version }.GetNewClosure()

    $taskContext = New-WhiskeyTestContext -ForBuildRoot 'Repo' @byWhoArg
    $taskContext.Version.SemVer2 = [SemVersion.SemanticVersion]$Version
    $taskContext.Version.Version = [version]('{0}.{1}.{2}' -f $taskContext.Version.SemVer2.Major,$taskContext.Version.SemVer2.Minor,$taskContext.Version.SemVer2.Patch)
    $taskContext.Version.SemVer2NoBuildMetadata = ([SemVersion.SemanticVersion]$taskContext.Version.SemVer2)
    if( $taskContext.Version.SemVer2.Prerelease )
    {
        $taskContext.Version.SemVer2NoBuildMetadata = [SemVersion.SemanticVersion]('{0}-{1}' -f $taskContext.Version.SemVer2NoBuildMetadata,$taskContext.Version.SemVer2.Prerelease)
    }

    if( $ForApplicationName )
    {
        $taskContext.ApplicationName = $ForApplicationName
    }
    
    $threwException = $false
    $At = $null

    $Global:Error.Clear()

    if( $WhenCleaning )
    {
        $taskContext.RunMode = 'Clean'
    }
        
    function Get-TempDirCount
    {
        Get-ChildItem -Path $env:TEMP -Filter ('Whiskey+Invoke-WhiskeyProGetUniversalPackageTask+{0}+*' -f $Name) | 
            Measure-Object | 
            Select-Object -ExpandProperty Count
    }

    $preTempDirCount = Get-TempDirCount
    try
    {
        $At = Invoke-WhiskeyProGetUniversalPackageTask -TaskContext $taskContext -TaskParameter $taskParameter |
                Where-Object { $_ -like '*.upack' } | 
                Where-Object { Test-Path -Path $_ -PathType Leaf }
    }
    catch
    {
        $threwException = $true
        Write-Error -ErrorRecord $_
    }
    $postTempDirCount = Get-TempDirCount

    if( $ShouldReturnNothing -or $ShouldFailWithErrorMessage )
    {
        It 'should not return package info' {
            $At | Should BeNullOrEmpty
        }
    }
    else
    {
        It 'should return package info' {
            $At | Should Exist
        }
    }

    if( $ShouldWriteNoErrors )
    {
        ThenTaskSucceeds
    }

    if( $ShouldFailWithErrorMessage )
    {
        It 'should fail with a terminating error' {
            $threwException | Should Be $true
        }

        ThenTaskFails $ShouldFailWithErrorMessage
    }
    else
    {
        It 'should not fail' {
            $threwException | Should Be $false
        }
    }

    #region
    $expandPath = Join-Path -Path $TestDrive.FullName -ChildPath 'Expand'
    $packageContentsPath = Join-Path -Path $expandPath -ChildPath 'package'
    $packageName = '{0}.{1}.upack' -f $Name,($taskContext.Version.SemVer2NoBuildMetadata-replace '[\\/]','-')
    $outputRoot = Get-WhiskeyOutputDirectory -WorkingDirectory $taskContext.BuildRoot
    $packagePath = Join-Path -Path $outputRoot -ChildPath $packageName

    It 'should cleanup temporary directories' {
        $postTempDirCount | Should Be $preTempDirCount
    }

    if( $ShouldNotCreatePackage )
    {
        It 'should not create a package' {
            $packagePath | Should Not Exist
        }
        return
    }
    else
    {
        It 'should create a package' {
            $packagePath | Should Exist
        }
    }

    Expand-Item -Path $packagePath -OutDirectory $expandPath

    $upackJsonPath = Join-Path -Path $expandPath -ChildPath 'upack.json'

    Context 'the package' {
        foreach( $itemName in $MissingRootItems )
        {
            It ('should not include {0} item' -f $itemName) {
                Join-Path -Path $packageContentsPath -ChildPath $itemName | Should Not Exist
            }
        }

        foreach( $itemName in $HasRootItems )
        {
            $dirPath = Join-Path -Path $packageContentsPath -ChildPath $itemName
            It ('should include {0} item' -f $itemName) {
                 $dirpath | Should Exist
            }
            foreach( $fileName in $HasFiles )
            {
                It ('should include {0}\{1} file' -f $itemName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Exist
                }
            }

            foreach( $fileName in $HasThirdPartyFile )
            {
                It ('should not include {0}\{1} file' -f $itemName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Not Exist
                }
            }
        }

        $versionJsonPath = Join-Path -Path $packageContentsPath -ChildPath 'version.json'
        It 'should include version.json' {
            $versionJsonPath | Should Exist
        }

        $version = Get-Content -Path $versionJsonPath -Raw | ConvertFrom-Json
        It 'version.json should have Version property' {
            $version.Version | Should BeOfType ([string])
            $version.Version | Should Be $taskContext.Version.Version.ToString()
        }
        It 'version.json should have PrereleaseMetadata property' {
            $version.PrereleaseMetadata | Should BeOfType ([string])
            $version.PrereleaseMetadata | Should Be $taskContext.Version.SemVer2.Prerelease.ToString()
        }
        It 'version.json shuld have BuildMetadata property' {
            $version.BuildMetadata | Should BeOfType ([string])
            $version.BuildMetadata | Should Be $taskContext.Version.SemVer2.Build.ToString()
        }
        It 'version.json should have full semantic version' {
            $version.SemanticVersion | Should BeOfType ([string])
            $version.SemanticVersion | Should Be $taskContext.Version.SemVer2.ToString()
        }
        It 'version.json should have release version' {
            $version.ReleaseVersion | Should BeOfType ([string])
            $version.ReleaseVersion | Should Be $taskContext.Version.SemVer2NoBuildMetadata.ToString()
        }

        if( $NotHasFiles )
        {
            foreach( $item in $NotHasFiles )
            {
                It ('should exclude {0} files' -f $item ) {
                    Get-ChildItem -Path $packageContentsPath -Filter $item -Recurse | Should BeNullOrEmpty
                }
            }
        }

        It 'should include ProGet universal package metadata (upack.json)' {
            $upackJsonPath | Should Exist
        }

        foreach( $itemName in $HasThirdPartyRootItem )
        {
            $dirPath = Join-Path -Path $packageContentsPath -ChildPath $itemName
            It ('should include {0} third-party root item' -f $itemName) {
                 $dirpath | Should Exist
            }
            
            foreach( $fileName in $HasThirdPartyFile )
            {
                It ('should include {0}\{1} third-party file' -f $itemName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Exist
                }
            }
        }
    }

    Context 'upack.json' {
        $upackInfo = Get-Content -Raw -Path $upackJsonPath | ConvertFrom-Json
        It 'should be valid json' {
            $upackInfo | Should Not BeNullOrEmpty
        }

        It 'should contain name' {
            $upackInfo.Name | Should Be $Name
        }

        It 'should contain title' {
            $upackInfo.title | Should Be $Name
        }

        It 'should contain version' {
            $upackInfo.Version | Should Be $taskContext.Version.SemVer2NoBuildMetadata.ToString()
        }

        It 'should contain description' {
            $upackInfo.Description | Should Be $Description
        }
    }
    #endregion
}

function Given7ZipIsInstalled
{
    Install-WhiskeyTool -NuGetPackageName '7-zip.x64' -Version '16.2.1' -DownloadRoot (Get-BuildRoot)
}

function Initialize-Test
{
    param( 
        [string[]]
        $DirectoryName,

        [string[]]
        $FileName,

        [string[]]
        $RootFileName,

        [Switch]
        $WhenUploadFails,
        
        [Switch]
        $OnFeatureBranch,

        [Switch]
        $OnMasterBranch,

        [Switch]
        $OnReleaseBranch,

        [Switch]
        $OnPermanentReleaseBranch,

        [Switch]
        $OnDevelopBranch,

        [Switch]
        $OnHotFixBranch,

        [Switch]
        $OnBugFixBranch,

        [string]
        $SourceRoot,

        [Switch]
        $AsDeveloper
    )

    $repoRoot = Get-BuildRoot
    Install-Directory -Path $repoRoot
    if( -not $SourceRoot )
    {
        $SourceRoot = $repoRoot
    }
    else
    {
        $SourceRoot = Join-Path -Path $repoRoot -ChildPath $SourceRoot
    }
    Install-Directory -Path $repoRoot

    $DirectoryName | ForEach-Object { 
        $dirPath = $_
        $dirPath = Join-Path -Path $SourceRoot -ChildPath $_
        Install-Directory -Path $dirPath
        foreach( $file in $FileName )
        {
            New-Item -Path (Join-Path -Path $dirPath -ChildPath $file) -ItemType 'File' | Out-Null
        }
    }

    foreach( $itemName in $RootFileName )
    {
        New-Item -Path (Join-Path -Path $SourceRoot -ChildPath $itemName) -ItemType 'File' | Out-Null
    }

    if( -not $AsDeveloper )
    {
        $gitBranch = 'origin/develop'
        if( $OnFeatureBranch )
        {
            $gitBranch = 'origin/feature/fubar'
        }
        if( $OnMasterBranch )
        {
            $gitBranch = 'origin/master'
        }
        if( $OnReleaseBranch )
        {
            $gitBranch = 'origin/release/5.1'
        }
        if( $OnPermanentReleaseBranch )
        {
            $gitBranch = 'origin/release'
        }
        if( $OnHotFixBranch )
        {
            $gitBranch = 'origin/hotfix/snafu'
        }
        if( $OnBugFixBranch )
        {
            $gitBranch = 'origin/bugfix/fubarnsafu'
        }

        $filter = { $Path -eq 'env:GIT_BRANCH' }
        $mock = { [pscustomobject]@{ Value = $gitBranch } }.GetNewClosure()
        Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -ParameterFilter $filter -MockWith $mock
        Mock -CommandName 'Get-Item' -ParameterFilter $filter -MockWith $mock
    }

    return $repoRoot
}

function Then7zipShouldNotExist
{
    It 'should delete 7zip NuGet package' {
        Join-Path -Path (Get-BuildRoot) -ChildPath 'packages\7-zip*' | Should -Not -Exist
    }
}




function New-TaskParameter
{
     @{ Name = 'fubar' ; Description = 'fubar'; Include = 'fubar'; Path = '.'; ThirdPartyPath = 'fubar' }
}

function Get-BuildRoot
{
    $buildRoot = (Join-Path -Path $TestDrive.FullName -ChildPath 'Repo')
    New-Item -Path $buildRoot -ItemType 'Directory' -Force -ErrorAction Ignore | Out-Null
    return $buildRoot
}

function GivenARepositoryWithFiles
{
    param(
        [string[]]
        $Path
    )

    $buildRoot = Get-BuildRoot

    foreach( $item in $Path )
    {
        $parent = $item | Split-Path
        if( $parent )
        {
            New-Item -Path (Join-Path -Path $buildRoot -ChildPath $parent) -ItemType 'Directory' -Force -ErrorAction Ignore
        }

        New-Item -Path (Join-Path -Path $buildRoot -ChildPath $item) -ItemType 'File'
    }
}

function WhenPackaging
{
    [CmdletBinding()]
    param(
        $WithPackageName = $defaultPackageName,
        $WithDescription = $defaultDescription,
        [object[]]
        $Paths,
        [object[]]
        $WithWhitelist,
        [object[]]
        $ThatExcludes,
        $FromSourceRoot,
        [object[]]
        $WithThirdPartyPath,
        $WithVersion = $defaultVersion,
        $WithApplicationName,
        [Switch]
        $ByDeveloper,
        [object[]]
        $CompressionLevel
    )
    $taskParameter = @{ }
    if( $WithPackageName )
    {
        $taskParameter['Name'] = $WithPackageName
    }
    if( $WithDescription )
    {
        $taskParameter['Description'] = $WithDescription
    }
    if( $Paths )
    {
        $taskParameter['Path'] = $Paths
    }
    if( $WithWhitelist )
    {
        $taskParameter['Include'] = $WithWhitelist
    }
    if( $ThatExcludes )
    {
        $taskParameter['Exclude'] = $ThatExcludes
    }
    if( $WithThirdPartyPath )
    {
        $taskParameter['ThirdPartyPath'] = $WithThirdPartyPath
    }
    if( $FromSourceRoot )
    {
        $taskParameter['SourceRoot'] = $FromSourceRoot
    }
    if( $CompressionLevel )
    {
        $taskParameter['CompressionLevel'] = $CompressionLevel
    }

    $byWhoArg = @{ }
    if( $ByDeveloper )
    {
        $byWhoArg['ByDeveloper'] = $true
    }
    else
    {
        $byWhoArg['ByBuildServer'] = $true
    }
    
    Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return [SemVersion.SemanticVersion]$WithVersion }.GetNewClosure()

    $taskContext = New-WhiskeyTestContext -ForBuildRoot 'Repo' @byWhoArg -ForVersion $WithVersion
    if( $WithApplicationName )
    {
        $taskContext.ApplicationName = $WithApplicationName
    }
    
    Mock -CommandName 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey'
    
    $threwException = $false
    $At = $null

    $Global:Error.Clear()

    function Get-TempDirCount
    {
        Get-ChildItem -Path $env:TEMP -Filter 'Whiskey+Invoke-WhiskeyProGetUniversalPackageTask+*' | 
            Measure-Object | 
            Select-Object -ExpandProperty Count
    }
    $preTempDirCount = Get-TempDirCount
    try
    {
        Invoke-WhiskeyProGetUniversalPackageTask -TaskContext $taskContext -TaskParameter $taskParameter
    }
    catch
    {
        $threwException = $true
        Write-Error -ErrorRecord $_
    }
    $postTempDirCount = Get-TempDirCount
}

function Expand-Package
{
    param(
        $PackageName = $defaultPackageName,
        $PackageVersion = $defaultVersion
    )

    $packageName = '{0}.{1}.upack' -f $PackageName,($PackageVersion -replace '[\\/]','-')
    $outputRoot = Get-BuildRoot
    $outputRoot = Join-Path -Path $outputRoot -ChildPath '.output'
    $packagePath = Join-Path -Path $outputRoot -ChildPath $packageName

    It 'should create a package' {
        $packagePath | Should Exist
    }

    $expandPath = Join-Path -Path $TestDrive.FullName -ChildPath 'Expand'
    if( -not (Test-Path -Path $expandPath -PathType Container) )
    {
        Expand-Item -Path $packagePath -OutDirectory $expandPath
    }
    return $expandPath
}

function Get-PackageSize
{
    param(
        $PackageName = $defaultPackageName,
        $PackageVersion = $defaultVersion
    )

    $packageName = '{0}.{1}.upack' -f $PackageName,($PackageVersion -replace '[\\/]','-')
    $outputRoot = Get-BuildRoot
    $outputRoot = Join-Path -Path $outputRoot -ChildPath '.output'
    $packagePath = Join-Path -Path $outputRoot -ChildPath $packageName
    $packageLength = (get-item $packagePath).Length
    return $packageLength
}

function ThenPackageShouldInclude
{
    param(
        $PackageName = $defaultPackageName,
        $PackageVersion = $defaultVersion,
        [Parameter(Position=0)]
        [string[]]
        $Path
    )

    $expandPath = Expand-Package -PackageName $PackageName -PackageVersion $PackageVersion

    $Path += @( 'version.json' )
    $packageRoot = Join-Path -Path $expandPath -ChildPath 'package'
    foreach( $item in $Path )
    {
        $expectedPath = Join-Path -Path $packageRoot -ChildPath $item
        It ('should include {0}' -f $item) {
            $expectedPath | Should Exist
        }
    }
}

function ThenPackageShouldNotInclude
{
    param(
        [string[]]
        $Path
    )

    $expandPath = Expand-Package
    $packageRoot = Join-Path -Path $expandPath -ChildPath 'package'

    foreach( $item in $Path )
    {
        It ('package should not include {0}' -f $item) {
            (Join-Path -Path $packageRoot -ChildPath $item) | Should -Not -Exist
        }
    }
}

function ThenPackageShouldbeBeCompressed
{
    param(
        $PackageName = $defaultPackageName,
        $PackageVersion = $defaultVersion,
        [Parameter(Position=0)]
        [string[]]
        $Path,

        [Int]
        $ExpectedPackageSize
    )

    $packageSize = Get-PackageSize -PackageName $PackageName -PackageVersion $PackageVersion
    It ('should have a compressed package size of {0}' -f $ExpectedPackageSize) {
        $packageSize | Should -Be $ExpectedPackageSize
    }
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when packaging everything in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -HasRootItems $dirNames `
                                            -HasFiles 'html.html' `
                                            -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when packaging root files' {
    $file = 'project.json'
    $thirdPartyFile = 'thirdparty.txt'
    $outputFilePath = Initialize-Test -RootFileName $file,$thirdPartyFile
    Assert-NewWhiskeyProGetUniversalPackage -ForPath $file `
                                            -WithThirdPartyRootItem $thirdPartyFile `
                                            -HasThirdPartyRootItem $thirdPartyFile `
                                            -HasRootItems $file `
                                            -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when packaging everything in a directory as a developer' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames `
                                      -AsDeveloper

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -HasRootItems $dirNames `
                                            -HasFiles 'html.html' `
                                            -WhenRunByDeveloper `
                                            -ShouldNotCreatePackage `
                                            -ShouldWriteNoErrors `
                                            -ShouldReturnNothing
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when packaging whitelisted files in a directory' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'code.cs', 'style.css' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html','*.css' `
                                            -HasRootItems $dirNames `
                                            -HasFiles 'html.html','style.css' `
                                            -NotHasFiles 'code.cs' `
                                            -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when packaging multiple directories' {
    $dirNames = @( 'dir1', 'dir1\sub', 'dir2' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1','dir2' `
                                            -ThatIncludes '*.html' `
                                            -HasRootItems $dirNames `
                                            -HasFiles 'html.html' `
                                            -NotHasFiles 'code.cs' `
                                            -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when whitelist includes items that need to be excluded' {    
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'html2.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -ThatExcludes 'html2.html','sub' `
                                            -HasRootItems 'dir1' `
                                            -HasFiles 'html.html' `
                                            -NotHasFiles 'html2.html','sub' `
                                            -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when paths don''t exist' {

    $Global:Error.Clear()

    Initialize-Test

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1','dir2' `
                                            -ThatIncludes '*' `
                                            -ShouldFailWithErrorMessage '(don''t|does not) exist' `
                                            -ShouldNotCreatePackage `
                                            -ErrorAction SilentlyContinue `
                                            -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when path contains known directories to exclude' {
    $dirNames = @( 'dir1', 'dir1/.hg', 'dir1/.git', 'dir1/obj', 'dir1/sub/.hg', 'dir1/sub/.git', 'dir1/sub/obj' )
    $filenames = 'html.html'
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $filenames
    
    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -HasRootItems 'dir1' `
                                            -HasFiles 'html.html' `
                                            -NotHasFiles '.git','.hg','obj' `
                                            -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when including third-party items' {
    $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
    $fileNames = @( 'html.html', 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -ThatExcludes 'thirdparty.txt' `
                                            -HasRootItems 'dir1' `
                                            -HasFiles 'html.html' `
                                            -WithThirdPartyRootItem 'thirdparty','thirdpart2' `
                                            -HasThirdPartyRootItem 'thirdparty','thirdpart2' `
                                            -HasThirdPartyFile 'thirdparty.txt' `
                                            -WhenRunByBuildServer
}

foreach( $parameterName in @( 'Name', 'Description', 'Include' ) )
{
    Describe ('Invoke-WhiskeyProGetUniversalPackageTask.when {0} property is omitted' -f $parameterName) {
        $parameter = @{
                        Name = 'Name';
                        Include = 'Include';
                        Description = 'Description';
                        Path = 'Path' 
                      }
        $parameter.Remove($parameterName)

        $context = New-WhiskeyTestContext -ForDeveloper
        $Global:Error.Clear()
        $threwException = $false
        try
        {
            Invoke-WhiskeyProGetUniversalPackageTask -TaskContext $context -TaskParameter $parameter
        }
        catch
        {
            $threwException = $true
            Write-Error -ErrorRecord $_ -ErrorAction SilentlyContinue
        }

        It 'should fail' {
            $threwException | Should Be $true
            $Global:Error | Should BeLike ('*Property ''{0}'' is mandatory.' -f $parameterName)
        }
    }
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when path to package doesn''t exist' {
    $context = New-WhiskeyTestContext -ForDeveloper

    $Global:Error.Clear()

    It 'should throw an exception' {
        { Invoke-WhiskeyProGetUniversalPackageTask -TaskContext $context -TaskParameter @{ Name = 'fubar' ; Description = 'fubar'; Include = 'fubar'; Path = 'fubar' } } | Should Throw
    }

    It 'should mention path in error message' {
        $Global:Error | Should BeLike ('* Path`[0`] ''{0}*'' does not exist.' -f (Join-Path -Path $context.BuildRoot -ChildPath 'fubar'))
    }
}
Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when path to third-party item doesn''t exist' {
    $filter = { $PropertyName -eq 'Path' } 
    Mock -CommandName 'Resolve-WhiskeyTaskPath' -ModuleName 'Whiskey' -ParameterFilter $filter -MockWith { return $True }

    $context = New-WhiskeyTestContext -ForDeveloper

    $Global:Error.Clear()

    It 'should throw an exception' {
        { Invoke-WhiskeyProGetUniversalPackageTask -TaskContext $context -TaskParameter (New-TaskParameter) } | Should Throw
    }

    It 'should mention path in error message' {
        $Global:Error | Should BeLike ('* ThirdPartyPath`[0`] ''{0}*'' does not exist.' -f (Join-Path -Path $context.BuildRoot -ChildPath 'fubar'))
    }
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when application root isn''t the root of the repository' {
    $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
    $fileNames = @( 'html.html', 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -SourceRoot 'app'

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -ThatExcludes 'thirdparty.txt' `
                                            -HasRootItems 'dir1' `
                                            -HasFiles 'html.html' `
                                            -WithThirdPartyRootItem 'thirdparty','thirdpart2' `
                                            -HasThirdPartyRootItem 'thirdparty','thirdpart2' `
                                            -HasThirdPartyFile 'thirdparty.txt' `
                                            -FromSourceRoot 'app' `
                                            -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when custom application root doesn''t exist' {
    $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
    $fileNames = @( 'html.html', 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames
    $context = New-WhiskeyTestContext -ForDeveloper

    $Global:Error.Clear()

    $parameter = New-TaskParameter
    $parameter['SourceRoot'] = 'app'

    { Invoke-WhiskeyProGetUniversalPackageTask -TaskContext $context -TaskParameter $parameter } | Should Throw

    ThenTaskFails 'SourceRoot\b.*\bapp\b.*\bdoes not exist'
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when packaging everything with a custom application name' {
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )

    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames `
                                      -OnDevelopBranch

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -HasRootItems $dirNames `
                                            -HasFiles 'html.html' `
                                            -ForApplicationName 'foo' `
                                            -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when cleaning' {
    $file = 'project.json'    
    Given7ZipIsInstalled
    $outputFilePath = Initialize-Test -RootFileName $file
    Assert-NewWhiskeyProGetUniversalPackage -ForPath $file `
                                            -WhenCleaning `
                                            -ShouldReturnNothing `
                                            -ShouldNotCreatePackage `
                                            -WhenRunByBuildServer
    Then7zipShouldNotExist
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when packaging given a full relative path' {
    $file = 'project.json'
    $directory = 'relative'
    $path = ('{0}\{1}' -f ($directory, $file))    

    $outputFilePath = Initialize-Test -DirectoryName $directory -FileName $file
    Assert-NewWhiskeyProGetUniversalPackage -ForPath $path -HasRootItems $path -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when packaging given a full relative path with override syntax' {
    $file = 'project.json'
    $directory = 'relative'
    $path = ('{0}\{1}' -f ($directory, $file))
    $forPath = @{ $path = $file }

    $outputFilePath = Initialize-Test -DirectoryName $directory -FileName $file
    Assert-NewWhiskeyProGetUniversalPackage -ForPath $forPath -HasRootItems $file  -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when including third-party items with override syntax' {
    $dirNames = @( 'dir1', 'app\thirdparty')
    $fileNames = @( 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatExcludes 'thirdparty.txt' `
                                            -HasRootItems 'dir1' `
                                            -WithThirdPartyRootItem @{ 'app\thirdparty' = 'thirdparty' } `
                                            -HasThirdPartyRootItem 'thirdparty' `
                                            -HasThirdPartyFile 'thirdparty.txt'  `
                                            -WhenRunByBuildServer
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when package is empty' {
    GivenARepositoryWithFiles 'file.txt'
    WhenPackaging -WithWhitelist "*.txt"
    ThenPackageShouldInclude
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTas.when path contains wildcards' {
    GivenARepositoryWithFiles 'one.ps1','two.ps1','three.ps1'
    WhenPackaging -Paths '*.ps1' -WithWhitelist '*.txt'
    ThenPackageShouldInclude 'one.ps1','two.ps1','three.ps1'
}


Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when packaging a directory' {
    GivenARepositoryWithFiles 'dir1\subdir\file.txt'
    WhenPackaging -Paths 'dir1\subdir' -WithWhitelist "*.txt"
    ThenPackageShouldInclude 'dir1\subdir\file.txt'
    ThenPackageShouldNotInclude ('dir1\{0}' -f $defaultPackageName)
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when compressionLevel of 9 is included' {
    GivenARepositoryWithFiles 'one.ps1'
    WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1" -CompressionLevel 9
    ThenPackageShouldbeBeCompressed 'one.ps1' -ExpectedPackageSize 798
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when compressionLevel is not included' {
    GivenARepositoryWithFiles 'one.ps1'
    WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1"
    ThenPackageShouldbeBeCompressed 'one.ps1' -ExpectedPackageSize 809
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when a bad compressionLevel is included' {
    GivenARepositoryWithFiles 'one.ps1'
    WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1" -CompressionLevel "this is no good" -ErrorAction SilentlyContinue
    ThenTaskFails 'not a valid Compression Level'
}

Describe 'Invoke-WhiskeyProGetUniversalPackageTask.when compressionLevel of 7 is included as a string' {
    GivenARepositoryWithFiles 'one.ps1'
    WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1" -CompressionLevel "7"
    ThenPackageShouldbeBeCompressed 'one.ps1' -ExpectedPackageSize 798
}
