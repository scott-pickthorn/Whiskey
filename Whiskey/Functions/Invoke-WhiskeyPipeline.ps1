
function Invoke-WhiskeyPipeline
{
    <#
    .SYNOPSIS
    Invokes Whiskey pipelines.

    .DESCRIPTION
    The `Invoke-WhiskeyPipeline` function runs the tasks in a pipeline. Pipelines are properties in a `whiskey.yml` under which one or more tasks are defined. For example, this `whiskey.yml` file:

        BuildTasks:
        - TaskOne
        - TaskTwo
        PublishTasks:
        - TaskOne
        - Task

    Defines two pipelines: `BuildTasks` and `PublishTasks`.

    .EXAMPLE
    Invoke-WhiskeyPipeline -Context $context -Name 'BuildTasks'

    Demonstrates how to run the tasks in a `BuildTasks` pipeline. The `$context` object is created by calling `New-WhiskeyContext`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The current build context. Use the `New-WhiskeyContext` function to create a context object.
        $Context,

        [Parameter(Mandatory=$true)]
        [string]
        # The name of pipeline to run, e.g. `BuildTasks` would run all the tasks under a property named `BuildTasks`. Pipelines are properties in your `whiskey.yml` file that are lists of Whiskey tasks to run.
        $Name
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $config = $Context.Configuration
    $Context.PipelineName = $Name

    if( -not $config.ContainsKey($Name) )
    {
        Stop-Whiskey -Context $Context -Message ('Pipeline ''{0}'' does not exist. Create a pipeline by defining a ''{0}'' property:
        
    {0}:
    - TASK_ONE
    - TASK_TWO
    
' -f $Name)
        return
    }

    $taskIdx = -1
    if( $config[$Name] -is [string]  )
    {
        Write-Warning -Message ('It looks like pipeline ''{0}'' doesn''t have any tasks.' -f $Context.ConfigurationPath)
        $config[$Name] = @()
    }

    foreach( $taskItem in $config[$Name] )
    {
        $taskIdx++
        if( $taskItem -is [string] )
        {
            $taskName = $taskItem
            $taskItem = @{ }
        }
        elseif( $taskItem -is [hashtable] )
        {
            $taskName = $taskItem.Keys | Select-Object -First 1
            $taskItem = $taskItem[$taskName]
            if( -not $taskItem )
            {
                $taskItem = @{ }
            }
        }
        else
        {
            continue
        }

        $Context.TaskIndex = $taskIdx

        Invoke-WhiskeyTask -TaskContext $Context -Name $taskName -Parameter $taskItem
    }
}