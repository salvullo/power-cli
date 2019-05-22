param(
    [string] $schedule = "daily"
)

If ( ! (Get-module VMware.VimAutomation.core )) {
 
    get-module -name VMware* -ListAvailable | Import-Module
     
}

#Stop an error from occurring when a transcript is already stopped
$ErrorActionPreference = "SilentlyContinue"
Stop-Transcript | out-null
 
#Reset the error level before starting the transcript
$ErrorActionPreference = "Continue"
Start-Transcript -path C:\temp\VMSnapshot.log -append

#Get the Credentials
$creds = Get-VICredentialStoreItem -file C:\Users\Administrator\In.creds
 
#Connect to the server using the credentials file
Connect-VIServer -Server $creds.host -User $creds.User -Password $creds.Password
    
    #Get all VMs having ScheduleSnapshot set to $schedule 
    $VMs = @(Get-VM | Get-Annotation -CustomAttribute "SnapshotSchedule" |
        Where-Object { $_.Value -eq $schedule } | Sort-Object AnnotatedEntity)

    ForEach ($VM in $VMs) {

        $name = $VM.AnnotatedEntity.Name
        $snapName = Get-Date -Format "yyyyMMdd-HHmm"

        # Creating snapshot
        Write-Host "Creating snapshot for VM $name as $snapName"
        New-Snapshot -VM $VM.AnnotatedEntity -Name $snapName -Quiesce:$true -Confirm:$false

        # Cleaning up by removing oldest snaps
        $SNAPs = Get-Snapshot -VM $VM.AnnotatedEntity 
        $Retain = (Get-Annotation -Entity $VM.AnnotatedEntity -CustomAttribute "SnapshotRetain").Value -as [int]

        if ($SNAPs.Length -gt $Retain) {
            Write-Host "Removing oldest snapshots for VM $name"
            Remove-Snapshot -Snapshot (
                $SNAPs | Sort-Object -Descending Created | 
                Select-Object -Last ($SNAPs.Length - $Retain)
            ) -Confirm:$false
        }
    }

#Disconnect
Disconnect-VIServer -Force -Confirm:$false
Stop-Transcript
