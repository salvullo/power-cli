param(
    [string] $schedule = "weekly",
    [string] $dstHost = "10.55.9.215",
    [string] $dstDS = "Local2 (SM)"
)

If ( ! (Get-module VMware.VimAutomation.core )) {
 
    get-module -name VMware* -ListAvailable | Import-Module
     
}

#Stop an error from occurring when a transcript is already stopped
$ErrorActionPreference = "SilentlyContinue"
Stop-Transcript | out-null
 
#Reset the error level before starting the transcript
$ErrorActionPreference = "Continue"
Start-Transcript -path C:\temp\VMClone.log -append

#Get the Credentials
$creds = Get-VICredentialStoreItem -file C:\Users\Administrator\In.creds
 
#Connect to the server using the credentials file
Connect-VIServer -Server $creds.host -User $creds.User -Password $creds.Password
    
    #Get all VMs having ScheduleSnapshot set to $schedule 
    $VMs = @(Get-VM | Get-Annotation -CustomAttribute "BackupSchedule" |
        Where-Object { $_.Value -eq $schedule } | Sort-Object AnnotatedEntity)

    ForEach ($Entity in $VMs) {
        
        $VM = $Entity.AnnotatedEntity     
        
        # Find source datastore and select name
        $srcDS = Get-Datastore -RelatedObject $VM
        Write-Host "$VM's Datastore identified as $srcDS"

        # Get VM used space
        $VMSpace =  get-vm $VM | Select-Object UsedSpaceGb | Where-Object {$_ -match '\d{1,}\.\d{2}'} | ForEach-Object {$Matches[0]}
        Write-Host "$VM requires $VMSpace Gb"
 
        # Check destination datastore free space
        Write-Host "Check destination datastore free space"
        $dstSpace = get-datastore $dstDS | select-object FreeSpaceGB | Where-Object {$_ -match '\d{1,}\.\d{2}'} | ForEach-Object {$Matches[0]}
        Write-Host "$dstDS has $dstSpace Gb available"

        # Math to check available free space
        $dstAvail = $dstSpace - $VMSpace
        Write-Host "Space after clone: $dstAvail"
 
        # if free space check is good, proceed with clone.
        if ($dstAvail -lt '50') {
            
            Write-Host "Free space check failed, SKIP clone"

        } Else {

            Write-Host "Free space check pass, proceed with clone"
            $vmdatestamp = (Get-Date).tostring('yyyyMMdd-HHmmss')
            Write-Host "Start clone $VM to $VM-$vmdatestamp"
                     
            $VMclone = New-VM -Name $VM-$vmdatestamp -VM $VM -Datastore $dstDS `
               -DiskStorageFormat Thin -HARestartPriority Disabled `
               -VMHost $dstHost 
                        
            $VMclone | Set-VM -ToTemplate -Confirm:$false
                  
            # Cleaning up by removing oldest clones
            $CLONEs = Get-Template -Datastore $dstDS | Select-Object Name |
                Where-Object {$_ -match "$name-.*"}
            $Retain = (Get-Annotation -Entity $VMclone -CustomAttribute "BackupRetain").Value -as [int]

            if ($CLONEs.Length -gt $Retain) {
            
                Write-Host "Removing oldest backups for VM $name"
                
                Remove-Template  -Template (
                    $CLONEs | Sort-Object -Descending Created | 
                    Select-Object -Last ($CLONEs.Length - $Retain)
                ) -Confirm:$false
            }
        }
    }
     
#Disconnect
Disconnect-VIServer -Force -Confirm:$false
Stop-Transcript
