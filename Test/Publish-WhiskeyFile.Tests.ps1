
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$Script:taskFailed = $false
$Script:taskException = $null

function Get-BuildRoot
{
    Join-Path -Path $TestDrive.FullName -ChildPath 'Source'
}

function Get-DestinationRoot
{
    Join-Path -Path $TestDrive.FullName -ChildPath 'Destination'
}

function GivenFiles
{
    param(
        [string[]]
        $Path
    )

    $sourceRoot = Get-BuildRoot
    foreach( $item in $Path )
    {
        New-Item -Path (Join-Path -Path $sourceRoot -ChildPath $item) -ItemType 'File' -Force | Out-Null
    }
}

function GivenNoFilesToPublish
{
}

function GivenUserCannotCreateDestination
{
    param(
        [string[]]
        $To
    )

    $destinationRoot = Get-DestinationRoot
    foreach( $item in $To )
    {
        $destinationPath = Join-Path -Path $destinationRoot -ChildPath $item
        Mock -CommandName 'New-Item' `
             -ModuleName 'Whiskey' `
             -MockWith { Write-Error ('Access to the path ''{0}'' is denied.' -f $item) -ErrorAction SilentlyContinue }.GetNewClosure() `
             -ParameterFilter ([scriptblock]::Create("`$Path -eq '$destinationPath'"))
    }
}

function WhenPublishingFiles
{
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string[]]
        $Path,

        [string[]]
        $To
    )

    $taskContext = New-WhiskeyTestContext -ForBuildServer

    $taskParameter = @{ }
    $taskParameter['Path'] = $Path
    $destinationRoot = Get-DestinationRoot
    $To = $To | ForEach-Object { Join-Path -Path $destinationRoot -ChildPath $_ }
    if( -not $To )
    {
        $To = $destinationRoot
    }
    $taskParameter['DestinationDirectories'] = $To

    $taskContext.BuildRoot = Get-BuildRoot
    $Script:taskFailed = $false
    $Script:taskException = $null

    try
    {
        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'PublishFile'
    }
    catch
    {
        $Script:taskException = $_
        $Script:taskFailed = $true
    }
}

function ThenNothingPublished
{
    param(
        [string[]]
        $To
    )

    $destinationRoot = Get-DestinationRoot
    It 'should copy nothing' {
        foreach( $item in $To )
        {
            $fullPath = Join-Path -Path $destinationRoot -ChildPath $item 
            if( (Test-Path -Path $fullPath -PathType Container) )
            {
                Get-ChildItem -Path $fullPath | Should BeNullOrEmpty
            }
        }
    }
}

function ThenFilesPublished
{
    param(
        [string[]]
        $Path
    )

    $destinationRoot = Get-DestinationRoot

    It 'should copy files' {
        foreach( $item in $Path )
        {
            Join-Path -Path $destinationRoot -ChildPath $item  |
                Get-Item |
                Should Not BeNullOrEmpty
        }
    }
}

function ThenTaskFails
{
    param(
        $WithErrorMessage
    )

    It 'should throw an exception' {
        $Script:taskFailed | Should Be $true
        $Script:taskException | Should Match $WithErrorMessage
    }

}

Describe 'Publish-WhiskeyFile.when publishing a single file' {
    GivenFiles 'one.txt'
    WhenPublishingFiles 'one.txt' 
    ThenFilesPublished 'one.txt'
}

Describe 'Publish-WhiskeyFile.when publishing multiple files to a single destination' {
    GivenFiles 'one.txt','two.txt'
    WhenPublishingFiles 'one.txt','two.txt'
    ThenFilesPublished 'one.txt','two.txt'
}

Describe 'Publish-WhiskeyFile.when publishing files from different directories' {
    GivenFiles 'dir1\one.txt','dir2\two.txt'
    WhenPublishingFiles 'dir1\one.txt','dir2\two.txt'
    ThenFilesPublished 'one.txt','two.txt'
}

Describe 'Publish-WhiskeyFile.when publishing to multiple destinations' {
    GivenFiles 'one.txt'
    WhenPublishingFiles 'one.txt' -To 'dir1','dir2'
    ThenFilesPublished 'dir1\one.txt','dir2\one.txt'
}

Describe 'Publish-WhiskeyFile.when publishing files and user can''t create one of the destination directories' {
    GivenFiles 'one.txt'
    GivenUserCannotCreateDestination 'dir2'
    WhenPublishingFiles 'one.txt' -To 'dir1','dir2' -ErrorAction SilentlyContinue
    ThenTaskFails -WithErrorMessage 'Failed to create destination directory'
    ThenNothingPublished -To 'dir1','dir2'
}

Describe 'Publish-WhiskeyFile.when publishing nothing' {
    GivenNoFilesToPublish
    WhenPublishingFiles -ErrorAction SilentlyContinue
    ThenTaskFails -WithErrorMessage '''Path'' property is missing'
    ThenNothingPublished
}

Describe 'Publish-WhiskeyFile.when publishing a directory' {
    GivenFiles 'dir1\file1.txt'
    WhenPublishingFiles 'dir1' -ErrorAction SilentlyContinue
    ThenTaskFails 'only publishes files'
    ThenNothingPublished
}

