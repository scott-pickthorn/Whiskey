
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

InModuleScope -ModuleName 'Whiskey' {
    $buildID = '80'
    $branch = 'feature/fubar'
    $commitID = 'deadbeefdeadbeefdeadbeefdeadbeef'
    $appBuildMetadata = 'feature-fubar.deadbee'
    $buildServerBuildMetadata = '80.feature-fubar.deadbee'
    $developerBuildMetadata = '{0}-{1}' -f $env:USERNAME,$env:COMPUTERNAME

    function Assert-ConvertsTo
    {
        param(
            [Parameter(ValueFromPipeline=$true)]
            $InputObject,

            [string]
            $ByBuildServer,

            [string]
            $ByDeveloper,

            [string]
            $Prerelease = ''
        )

        process
        {
            $inputDesc = 'nothing'
            if( $InputObject )
            {
                $inputDesc = '[{0}]{1}' -f $InputObject.GetType().Name.ToLowerInvariant(),$InputObject
            }

            if( $Prerelease )
            {
                $inputDesc = '{0} and prerelease metadata' -f $inputDesc
            }

            Describe ('New-WhiskeySemanticVersion.when passed {0}' -f $inputDesc) {
                Context 'by build server' {
                    $buildInfo = New-WhiskeyBuildMetadataObject
                    $buildInfo.BuildNumber = $buildID
                    $buildInfo.ScmBranch = $branch
                    $buildInfo.ScmCommitID = $commitID
                    $buildInfo.BuildServerName = 'Jenkins'
                    It ('should convert to {0}' -f $ByBuildServer) {
                        New-WhiskeySemanticVersion -Version $InputObject -Prerelease $Prerelease -BuildMetadata $buildInfo | Should Be ([SemVersion.SemanticVersion]::Parse($ByBuildServer))
                    }
                }
                Context 'by developer' {
                    $buildInfo = New-WhiskeyBuildMetadataObject
                    It ('should convert to {0}' -f $ByDeveloper) {
                        New-WhiskeySemanticVersion -Version $InputObject -Prerelease $Prerelease -BuildMetadata $buildInfo | Should Be ([SemVersion.SemanticVersion]::Parse($ByDeveloper))
                    }
                }
            }
        }
    }

    $testCases = @{
                    '3.2.1+build.info' = '3.2.1';
                  }

    '3.2.1+build.info' | Assert-ConvertsTo -ByBuildServer ('3.2.1+{0}' -f $buildServerBuildMetadata)  -ByDeveloper ('3.2.1+{0}' -f $developerBuildMetadata)
    '3.2.1+build.info' | Assert-ConvertsTo -ByBuildServer ('3.2.1+{0}' -f $buildServerBuildMetadata)  -ByDeveloper ('3.2.1+{0}' -f $developerBuildMetadata) 
    2.0                | Assert-ConvertsTo -ByBuildServer ('2.0.0+{0}' -f $buildServerBuildMetadata)    -ByDeveloper ('2.0.0+{0}' -f $developerBuildMetadata)
    2.01               | Assert-ConvertsTo -ByBuildServer ('2.1.0+{0}' -f $buildServerBuildMetadata)    -ByDeveloper ('2.1.0+{0}' -f $developerBuildMetadata)
    2.001              | Assert-ConvertsTo -ByBuildServer ('2.1.0+{0}' -f $buildServerBuildMetadata)    -ByDeveloper ('2.1.0+{0}' -f $developerBuildMetadata)
    3                  | Assert-ConvertsTo -ByBuildServer ('3.0.0+{0}' -f $buildServerBuildMetadata)    -ByDeveloper ('3.0.0+{0}' -f $developerBuildMetadata)
    $dateBasedVersion = (Get-Date).ToString('yyyy.Mdd')
    (@{})['Version']   | Assert-ConvertsTo -ByBuildServer ('{0}.80+{1}' -F $dateBasedVersion,$buildServerBuildMetadata) -ByDeveloper ('{0}.0+{1}' -f $dateBasedVersion,$developerBuildMetadata)
    '5.6.7-rc.3'       | Assert-ConvertsTo -ByBuildServer ('5.6.7-rc.3+{0}' -f $buildServerBuildMetadata) -ByDeveloper ('5.6.7-rc.3+{0}' -f $developerBuildMetadata)
    '1'                | Assert-ConvertsTo -ByBuildServer ('1.0.0+{0}' -f $buildServerBuildMetadata)        -ByDeveloper ('1.0.0+{0}' -f $developerBuildMetadata)
    '1.32'             | Assert-ConvertsTo -ByBuildServer ('1.32.0+{0}' -f $buildServerBuildMetadata)       -ByDeveloper ('1.32.0+{0}' -f $developerBuildMetadata)
    '1.32.4'           | Assert-ConvertsTo -ByBuildServer ('1.32.4+{0}' -f $buildServerBuildMetadata)     -ByDeveloper ('1.32.4+{0}' -f $developerBuildMetadata)
    '1.0130'           | Assert-ConvertsTo -ByBuildServer ('1.130.0+{0}' -f $buildServerBuildMetadata)      -ByDeveloper ('1.130.0+{0}' -f $developerBuildMetadata)
    '1.5.6'            | Assert-ConvertsTo -Prerelease 'rc.4' -ByBuildServer ('1.5.6-rc.4+{0}' -f $buildServerBuildMetadata)      -ByDeveloper ('1.5.6-rc.4+{0}' -f $developerBuildMetadata)
    (@{})['Version']   | Assert-ConvertsTo -Prerelease 'rc.4' -ByBuildServer ('{0}.80-rc.4+{1}' -f $dateBasedVersion,$buildServerBuildMetadata)      -ByDeveloper ('{0}.0-rc.4+{1}' -f $dateBasedVersion,$developerBuildMetadata)
}