
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Use-CallerPreference.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Tasks\New-WhiskeyNuGetPackage.ps1' -Resolve)

$projectName ='NUnit2PassingTest.csproj' 
$context = $null
$nugetUri = $null
$apiKey = $null
$defaultVersion = '1.2.3'
$packageExists = $false
$publishFails = $false
$packageExistsCheckFails = $false
$threwException = $false
$byBuildServer = $false

function InitTest
{
    param(
    )

    $script:nugetUri = 'https://nuget.org'
    $script:apiKey = 'fubar:snafu'
    $script:packageExists = $false
    $script:publishFails = $false
    $script:packageExistsCheckFails = $false
    $script:path = $projectName
    $script:byBuildServer = $false
}

function GivenABuiltLibrary
{
    param(
        [Switch]
        $ThatDoesNotExist,

        [Switch]
        $InReleaseMode
    )

    $projectRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest'
    robocopy $projectRoot $TestDrive.FullName '/MIR' '/R:0'

    # Make sure output directory gets created by the task
    $buildConfig = 'Debug'
    if( $InReleaseMode )
    {
        $buildConfig = 'Release'
    }

    $project = Join-Path -Path $TestDrive.FullName -ChildPath $projectName -Resolve
    
    $propertyArg = @{}
    if( $InReleaseMode )
    {
        $propertyArg['Property'] = 'Configuration=Release'
    }

    Get-ChildItem -Path $TestDrive.FullName -File '*.sln' | ForEach-Object { & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\NuGet.exe' -Resolve) restore $_.FullName }# $project
    Invoke-WhiskeyMSBuild -Path $project -Target 'build' @propertyArg | Write-Verbose
}

function GivenRunByBuildServer
{
    $script:byBuildServer = $true
}

function GivenPath
{
    param(
        [string[]]
        $Path
    )

    $script:path = $Path
}

function GivenNoPath
{
    $script:path = $null
}

function WhenRunningNuGetPackTask
{
    [CmdletBinding()]
    param(
        [Switch]
        $Symbols
    )

    $byItDepends = @{}
    if( $byBuildServer )
    {
        $byItDepends['ForBuildServer'] = $true
    }
    else
    {
        $byItDepends['ForDeveloper'] = $true
    }
            
    $script:context = New-WhiskeyTestContext -ForVersion '1.2.3+buildstuff' @byItDepends -ForTaskName 'NuGetPack'
    
    Get-ChildItem -Path $context.OutputDirectory | Remove-Item -Recurse -Force

    $taskParameter = @{ }

    if( $path )
    {
        $taskParameter['Path'] = $path
    }

    if( $Symbols )
    {
        $taskParameter['Symbols'] = $true
    }

    $optionalParams = @{ }
    $script:threwException = $false
    try
    {
        $Global:error.Clear()
        New-WhiskeyNuGetPackage -TaskContext $Context -TaskParameter $taskParameter

    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }
}

function ThenTaskThrowsAnException
{
    param(
        $ExpectedErrorMessage
    )

    It 'should throw an exception' {
        $threwException | Should Be $true
    }

    It ('should throw an exception that matches /{0}/' -f $ExpectedErrorMessage) {
        $Global:Error | Should Not BeNullOrEmpty
        $lastError = $Global:Error[0]
        $lastError | Should -Match $ExpectedErrorMessage
    }
}

function ThenTaskSucceeds
{
    It 'should not throw an exception' {
        $threwException | Should Be $false
        $Global:Error | Should BeNullOrEmpty
    }
}

function ThenPackageCreated
{
    param(
        [Switch]
        $Symbols
    )

    $symbolsPath = Join-Path -Path $Context.OutputDirectory -ChildPath ('NUnit2PassingTest.{0}.symbols.nupkg' -f $Context.Version.SemVer1)
    $nonSymbolsPath = Join-Path -Path $Context.OutputDirectory -ChildPath ('NUnit2PassingTest.{0}.nupkg' -f $Context.Version.SemVer1)
    if( $Symbols )
    {
        It ('should create NuGet symbols package') {
            $symbolsPath | Should -Exist
        }

        It ('should create a non-symbols package') {
            $nonSymbolsPath | Should -Exist
        }
    }
    else
    {
        It ('should create NuGet package') {
            $nonSymbolsPath | Should -Exist
        }

        It ('should not create a symbols package') {
            $symbolsPath | Should -Not -Exist
        }
    }
 }

function ThenPackageNotCreated
{
    It 'should not create any .nupkg files' {
        (Join-Path -Path $context.OutputDirectory -ChildPath '*.nupkg') | Should Not Exist
    }
}

Describe 'New-WhiskeyNuGetPackage.when creating a NuGet package with an invalid project' {
    InitTest
    GivenABuiltLibrary
    GivenPath -Path 'I\do\not\exist.csproj'
    WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
    ThenPackageNotCreated
    ThenTaskThrowsAnException 'does not exist'
}

Describe 'New-WhiskeyNuGetPackage.when creating a NuGet package' {
    InitTest
    GivenABuiltLibrary
    WhenRunningNuGetPackTask
    ThenTaskSucceeds
    ThenPackageCreated
}

Describe 'New-WhiskeyNuGetPackage.when creating a symbols NuGet package' {
    InitTest
    GivenABuiltLibrary
    WhenRunningNuGetPackTask -Symbols
    ThenTaskSucceeds
    ThenPackageCreated -Symbols
}

Describe 'New-WhiskeyNuGetPackage.when creating a package built in release mode' {
    InitTest
    GivenABuiltLibrary -InReleaseMode
    GivenRunByBuildServer
    WhenRunningNugetPackTask
    ThenTaskSucceeds
    ThenPackageCreated
}

Describe 'New-WhiskeyNuGetPackage.when creating multiple packages for publishing' {
    InitTest
    GivenABuiltLibrary
    GivenPath @( $projectName, $projectName )
    WhenRunningNugetPackTask 
    ThenPackageCreated
    ThenTaskSucceeds
}
