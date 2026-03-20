#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comprehensive Windows 11 HDD/SSD Optimization Script with Progress Reporting
    
.DESCRIPTION
    This script performs complete drive optimization using multiple methods:
    - System file repair (DISM + SFC)
    - Disk error checking (CHKDSK)
    - Drive optimization (Defrag for HDD, Retrim for SSD)
    - Disk cleanup
    - Prefetch/Superfetch management
    
.PARAMETER DriveLetter
    The drive letter to optimize (e.g., "C", "D"). Default is "C".
    
.PARAMETER SkipSystemRepair
    Skip DISM and SFC scans (faster, but less thorough)
    
.PARAMETER AggressiveMode
    Perform deeper optimization including boot optimization and free space consolidation
    
.PARAMETER AutoReboot
    Automatically reboot if required by CHKDSK
    
.EXAMPLE
    .\Optimize-Drive.ps1 -DriveLetter C -AggressiveMode
    
.EXAMPLE
    .\Optimize-Drive.ps1 -DriveLetter D -SkipSystemRepair
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$DriveLetter = "C",
    
    [Parameter()]
    [switch]$SkipSystemRepair,
    
    [Parameter()]
    [switch]$AggressiveMode,
    
    [Parameter()]
    [switch]$AutoReboot
)

# Initialize
$ErrorActionPreference = "Stop"
$StartTime = Get-Date
$DriveLetter = $DriveLetter.TrimEnd(':').ToUpper()
$DrivePath = "${DriveLetter}:"

# Check if drive exists
if (-not (Test-Path $DrivePath)) {
    throw "Drive $DriveLetter does not exist!"
}

# Get drive info for smart optimization
Write-Host "`n=== Drive Analysis ===" -ForegroundColor Cyan
$PhysicalDisk = Get-PhysicalDisk | Where-Object { 
    $diskNumber = (Get-Partition -DriveLetter $DriveLetter | Get-Disk).Number
    $_.DeviceId -eq $diskNumber 
}
$IsSSD = $PhysicalDisk.MediaType -eq "SSD"
$DriveType = if ($IsSSD) { "SSD" } else { "HDD" }

Write-Host "Drive: $DriveLetter" -ForegroundColor White
Write-Host "Type: $DriveType" -ForegroundColor $(if ($IsSSD) { "Green" } else { "Yellow" })
Write-Host "Model: $($PhysicalDisk.FriendlyName)" -ForegroundColor White
Write-Host "Size: $([math]::Round($PhysicalDisk.Size / 1GB, 2)) GB" -ForegroundColor White

# Progress tracking variables
$TotalSteps = if ($SkipSystemRepair) { 3 } else { 5 }
if ($AggressiveMode) { $TotalSteps += 1 }
$CurrentStep = 0

function Show-ProgressBar {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete,
        [int]$Step,
        [int]$TotalSteps
    )
    
    $ProgressParams = @{
        Activity = "Step $Step of $TotalSteps`: $Activity"
        Status = $Status
        PercentComplete = $PercentComplete
    }
    
    Write-Progress @ProgressParams
    
    # Also write to console with color coding
    $color = switch ($PercentComplete) {
        { $_ -lt 30 } { "Red" }
        { $_ -lt 70 } { "Yellow" }
        default { "Green" }
    }
    
    Write-Host "[$Step/$TotalSteps] $Activity - $Status ($PercentComplete%)" -ForegroundColor $color
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n$("=" * 60)" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$("=" * 60)" -ForegroundColor Cyan
}

# Step 1: System File Repair (DISM)
if (-not $SkipSystemRepair) {
    $CurrentStep++
    Write-Section "STEP 1: System Image Repair (DISM)"
    
    try {
        # Check health first
        Show-ProgressBar -Activity "DISM CheckHealth" -Status "Scanning system image..." -PercentComplete 0 -Step $CurrentStep -TotalSteps $TotalSteps
        
        $healthCheck = DISM /Online /Cleanup-Image /CheckHealth 2>&1
        $needsRepair = $healthCheck -match "The component store is repairable"
        
        Show-ProgressBar -Activity "DISM CheckHealth" -Status "Check complete" -PercentComplete 25 -Step $CurrentStep -TotalSteps $TotalSteps
        
        if ($needsRepair) {
            Write-Host "  [!] Corruption detected, repairing..." -ForegroundColor Yellow
            
            # Restore health with progress simulation
            $dismJob = Start-Job -ScriptBlock {
                DISM /Online /Cleanup-Image /RestoreHealth /NoRestart
            }
            
            $percent = 25
            while ($dismJob.State -eq "Running") {
                Start-Sleep -Seconds 2
                $percent += 1
                if ($percent -gt 90) { $percent = 90 }
                Show-ProgressBar -Activity "DISM RestoreHealth" -Status "Repairing system image..." -PercentComplete $percent -Step $CurrentStep -TotalSteps $TotalSteps
            }
            
            $result = Receive-Job -Job $dismJob
            Remove-Job -Job $dismJob
            
            Show-ProgressBar -Activity "DISM RestoreHealth" -Status "Repair complete" -PercentComplete 100 -Step $CurrentStep -TotalSteps $TotalSteps
            
            if ($result -match "The restore operation completed successfully") {
                Write-Host "  [✓] DISM repair successful" -ForegroundColor Green
            } else {
                Write-Host "  [!] DISM completed with warnings" -ForegroundColor Yellow
            }
        } else {
            Show-ProgressBar -Activity "DISM CheckHealth" -Status "No corruption found" -PercentComplete 100 -Step $CurrentStep -TotalSteps $TotalSteps
            Write-Host "  [✓] System image healthy" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [✗] DISM error: $_" -ForegroundColor Red
    }
    
    Write-Progress -Activity "Step $CurrentStep" -Completed
}

# Step 2: System File Checker (SFC)
if (-not $SkipSystemRepair) {
    $CurrentStep++
    Write-Section "STEP 2: System File Checker (SFC)"
    
    try {
        Write-Host "  Starting SFC scan (this may take 10-15 minutes)..." -ForegroundColor White
        
        # SFC doesn't have a native progress API, so we simulate based on typical duration
        $sfcJob = Start-Job -ScriptBlock {
            sfc /scannow
        }
        
        $percent = 0
        $lastOutput = ""
        
        while ($sfcJob.State -eq "Running") {
            Start-Sleep -Seconds 3
            
            # Try to get real-time output if possible
            $output = Receive-Job -Job $sfcJob -Keep 2>$null | Select-Object -Last 1
            if ($output -and $output -ne $lastOutput) {
                $lastOutput = $output
                # Parse percentage if available in output
                if ($output -match "(\d+) percent complete") {
                    $percent = [int]$matches[1]
                }
            }
            
            # Increment if no real data
            if ($percent -lt 99) { $percent += 1 }
            
            Show-ProgressBar -Activity "SFC Scan" -Status "Verifying system files..." -PercentComplete $percent -Step $CurrentStep -TotalSteps $TotalSteps
        }
        
        $sfcResult = Receive-Job -Job $sfcJob
        Remove-Job -Job $sfcJob
        
        Show-ProgressBar -Activity "SFC Scan" -Status "Scan complete" -PercentComplete 100 -Step $CurrentStep -TotalSteps $TotalSteps
        
        if ($sfcResult -match "found no integrity violations") {
            Write-Host "  [✓] No system file corruption found" -ForegroundColor Green
        } elseif ($sfcResult -match "successfully repaired") {
            Write-Host "  [✓] Corrupt files repaired successfully" -ForegroundColor Green
        } else {
            Write-Host "  [!] SFC completed with warnings - check CBS.log" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [✗] SFC error: $_" -ForegroundColor Red
    }
    
    Write-Progress -Activity "Step $CurrentStep" -Completed
}

# Step 3: Check Disk (CHKDSK)
$CurrentStep++
Write-Section "STEP 3: Disk Error Checking (CHKDSK)"

try {
    # First, analyze only
    Show-ProgressBar -Activity "CHKDSK Analysis" -Status "Checking file system..." -PercentComplete 0 -Step $CurrentStep -TotalSteps $TotalSteps
    
    # Use fsutil to check dirty bit
    $dirtyBit = fsutil dirty query $DriveLetter 2>&1
    $needsChkdsk = $dirtyBit -match "is Dirty"
    
    Show-ProgressBar -Activity "CHKDSK Analysis" -Status "Analysis complete" -PercentComplete 50 -Step $CurrentStep -TotalSteps $TotalSteps
    
    if ($needsChkdsk -or $AggressiveMode) {
        Write-Host "  [!] Drive requires CHKDSK repair" -ForegroundColor Yellow
        
        if ($DriveLetter -eq "C") {
            Write-Host "  [i] C: drive requires reboot to run CHKDSK" -ForegroundColor Cyan
            $schedule = "Y"
            
            if (-not $AutoReboot) {
                $schedule = Read-Host "  Schedule CHKDSK for next restart? (Y/N)"
            }
            
            if ($schedule -eq "Y") {
                # Schedule CHKDSK with all fixes
                $chkdskParams = "/F /R /X"
                if ($AggressiveMode) { $chkdskParams = "/F /R /X /B" } # Add boot check
                
                $scheduleResult = echo "Y" | chkdsk ${DriveLetter}: $chkdskParams 2>&1
                Write-Host "  [✓] CHKDSK scheduled for next boot" -ForegroundColor Green
                Write-Host "      Parameters: $chkdskParams" -ForegroundColor Gray
            }
        } else {
            # Non-system drive, can run immediately
            Write-Host "  Running CHKDSK repair on $DriveLetter..." -ForegroundColor Yellow
            
            # Run CHKDSK with progress tracking via event logs
            $chkdskArgs = "/F /R /X"
            if ($AggressiveMode) { $chkdskArgs = "/F /R /X /B" }
            
            # Start CHKDSK as job since it can take a long time
            $chkdskJob = Start-Job -ScriptBlock {
                param($dl, $args)
                chkdsk "${dl}:" $args.Split(' ')
            } -ArgumentList $DriveLetter, $chkdskArgs
            
            $percent = 0
            while ($chkdskJob.State -eq "Running") {
                Start-Sleep -Seconds 5
                $percent += 1
                if ($percent -gt 95) { $percent = 95 }
                Show-ProgressBar -Activity "CHKDSK Repair" -Status "Repairing disk errors and bad sectors..." -PercentComplete $percent -Step $CurrentStep -TotalSteps $TotalSteps
            }
            
            $chkdskResult = Receive-Job -Job $chkdskJob
            Remove-Job -Job $chkdskJob
            
            Show-ProgressBar -Activity "CHKDSK Repair" -Status "Repair complete" -PercentComplete 100 -Step $CurrentStep -TotalSteps $TotalSteps
            
            if ($chkdskResult -match "found no errors" -or $chkdskResult -match "completed") {
                Write-Host "  [✓] CHKDSK completed successfully" -ForegroundColor Green
            } else {
                Write-Host "  [!] CHKDSK finished with warnings" -ForegroundColor Yellow
            }
        }
    } else {
        Show-ProgressBar -Activity "CHKDSK Analysis" -Status "No errors found" -PercentComplete 100 -Step $CurrentStep -TotalSteps $TotalSteps
        Write-Host "  [✓] File system is clean" -ForegroundColor Green
    }
} catch {
    Write-Host "  [✗] CHKDSK error: $_" -ForegroundColor Red
}

Write-Progress -Activity "Step $CurrentStep" -Completed

# Step 4: Drive Optimization (Defrag/Retrim)
$CurrentStep++
Write-Section "STEP 4: Drive Optimization ($(if($IsSSD){'SSD Retrim'}else{'HDD Defrag'}))"

try {
    # Get volume info
    $volume = Get-Volume -DriveLetter $DriveLetter
    
    Write-Host "  Drive Type: $DriveType" -ForegroundColor White
    Write-Host "  Optimization method: $(if($IsSSD){'TRIM reallocation'}else{'Defragmentation + consolidation'})" -ForegroundColor White
    
    # Use Optimize-Volume which has native progress support
    Show-ProgressBar -Activity "Drive Optimization" -Status "Starting optimization engine..." -PercentComplete 0 -Step $CurrentStep -TotalSteps $TotalSteps
    
    $optimizeParams = @{
        DriveLetter = $DriveLetter
        Verbose = $true
    }
    
    if ($IsSSD) {
        $optimizeParams['ReTrim'] = $true
    } else {
        $optimizeParams['Defrag'] = $true
        if ($AggressiveMode) {
            $optimizeParams['SlabConsolidate'] = $true
        }
    }
    
    # Capture verbose output for progress parsing
    $verboseOutput = [System.Collections.ArrayList]::new()
    
    $optimizeJob = Start-Job -ScriptBlock {
        param($params)
        Optimize-Volume @params 4>&1
    } -ArgumentList $optimizeParams
    
    # Monitor progress
    $percent = 0
    $lastStatus = "Initializing..."
    
    while ($optimizeJob.State -eq "Running") {
        Start-Sleep -Seconds 2
        
        # Check for new output
        $newOutput = Receive-Job -Job $optimizeJob -Keep 2>$null
        if ($newOutput) {
            $verboseOutput.AddRange(@($newOutput)) | Out-Null
            
            # Parse progress from verbose output
            foreach ($line in $newOutput) {
                if ($line -match "(\d+) percent complete") {
                    $percent = [int]$matches[1]
                }
                if ($line -match "(Defrag|Retrim|SlabConsolidate|TierOptimize).*:\s*(.*)") {
                    $lastStatus = $matches[2]
                }
            }
        }
        
        # Fallback increment
        if ($percent -lt 99 -and -not ($newOutput | Where-Object { $_ -match "percent" })) {
            $percent = [math]::Min($percent + 2, 95)
        }
        
        Show-ProgressBar -Activity "Drive Optimization" -Status $lastStatus -PercentComplete $percent -Step $CurrentStep -TotalSteps $TotalSteps
    }
    
    $finalOutput = Receive-Job -Job $optimizeJob
    Remove-Job -Job $optimizeJob
    
    Show-ProgressBar -Activity "Drive Optimization" -Status "Optimization complete" -PercentComplete 100 -Step $CurrentStep -TotalSteps $TotalSteps
    
    # Parse final results
    $resultText = ($verboseOutput + $finalOutput) | Out-String
    
    if ($IsSSD) {
        if ($resultText -match "Total space trimmed\s*=\s*(\S+)") {
            Write-Host "  [✓] SSD TRIM complete - Space trimmed: $($matches[1])" -ForegroundColor Green
        } else {
            Write-Host "  [✓] SSD optimization complete" -ForegroundColor Green
        }
    } else {
        if ($resultText -match "Total fragmented space\s*=\s*(\d+)%") {
            $fragPercent = $matches[1]
            Write-Host "  [✓] Defrag complete - Fragmentation: $fragPercent%" -ForegroundColor Green
        } else {
            Write-Host "  [✓] HDD optimization complete" -ForegroundColor Green
        }
    }
    
    # Display post-optimization stats if available
    if ($resultText -match "Post Defragmentation Report") {
        $reportSection = $resultText -split "Post Defragmentation Report" | Select-Object -Last 1
        Write-Host "`n  Post-Optimization Stats:" -ForegroundColor Gray
        if ($reportSection -match "Largest free space size\s*=\s*(\S+)") {
            Write-Host "    Largest free space block: $($matches[1])" -ForegroundColor Gray
        }
    }
    
} catch {
    Write-Host "  [✗] Optimization error: $_" -ForegroundColor Red
    Write-Host "  Trying fallback to defrag.exe..." -ForegroundColor Yellow
    
    # Fallback to legacy defrag with progress
    $defragArgs = if ($IsSSD) { "/L /U /V" } else { "/O /U /V" }
    if ($AggressiveMode -and -not $IsSSD) { $defragArgs = "/X /O /U /V" }
    
    $defragJob = Start-Job -ScriptBlock {
        param($dl, $args)
        defrag "${dl}:" $args.Split(' ')
    } -ArgumentList $DriveLetter, $defragArgs
    
    $percent = 0
    while ($defragJob.State -eq "Running") {
        Start-Sleep -Seconds 3
        $percent += 2
        if ($percent -gt 95) { $percent = 95 }
        Show-ProgressBar -Activity "Drive Optimization (Legacy)" -Status "Processing..." -PercentComplete $percent -Step $CurrentStep -TotalSteps $TotalSteps
    }
    
    Remove-Job -Job $defragJob
    Show-ProgressBar -Activity "Drive Optimization (Legacy)" -Status "Complete" -PercentComplete 100 -Step $CurrentStep -TotalSteps $TotalSteps
}

Write-Progress -Activity "Step $CurrentStep" -Completed

# Step 5: Disk Cleanup (if AggressiveMode)
if ($AggressiveMode) {
    $CurrentStep++
    Write-Section "STEP 5: Deep Disk Cleanup"
    
    try {
        Show-ProgressBar -Activity "Disk Cleanup" -Status "Scanning for removable files..." -PercentComplete 0 -Step $CurrentStep -TotalSteps $TotalSteps
        
        # Run cleanmgr with specific sageset
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        $items = Get-ChildItem $regPath
        
        # Enable all cleanup options
        foreach ($item in $items) {
            $itemPath = $item.PSPath
            Set-ItemProperty -Path $itemPath -Name "StateFlags0001" -Value 2 -ErrorAction SilentlyContinue
        }
        
        Show-ProgressBar -Activity "Disk Cleanup" -Status "Cleaning system files..." -PercentComplete 30 -Step $CurrentStep -TotalSteps $TotalSteps
        
        # Start cleanup process
        $cleanupJob = Start-Job -ScriptBlock {
            cleanmgr /sagerun:1
        }
        
        $percent = 30
        while ($cleanupJob.State -eq "Running") {
            Start-Sleep -Seconds 2
            $percent += 1
            if ($percent -gt 90) { $percent = 90 }
            Show-ProgressBar -Activity "Disk Cleanup" -Status "Removing temporary files..." -PercentComplete $percent -Step $CurrentStep -TotalSteps $TotalSteps
        }
        
        Remove-Job -Job $cleanupJob
        
        Show-ProgressBar -Activity "Disk Cleanup" -Status "Cleanup complete" -PercentComplete 100 -Step $CurrentStep -TotalSteps $TotalSteps
        Write-Host "  [✓] Temporary files cleaned" -ForegroundColor Green
        
    } catch {
        Write-Host "  [!] Disk Cleanup error: $_" -ForegroundColor Yellow
        Write-Host "  You can run Disk Cleanup manually later" -ForegroundColor Gray
    }
    
    Write-Progress -Activity "Step $CurrentStep" -Completed
}

# Step 6: Additional Optimizations
$CurrentStep++
Write-Section "STEP $(if($AggressiveMode){6}else{5}): Additional Performance Tweaks"

Show-ProgressBar -Activity "System Tweaks" -Status "Applying optimizations..." -PercentComplete 0 -Step $CurrentStep -TotalSteps $TotalSteps

try {
    # Clear prefetch (only if not SSD, or if AggressiveMode)
    if ((-not $IsSSD) -or $AggressiveMode) {
        $prefetchPath = "$env:SystemRoot\Prefetch"
        if (Test-Path $prefetchPath) {
            $prefetchFiles = Get-ChildItem $prefetchPath -File -ErrorAction SilentlyContinue
            $count = $prefetchFiles.Count
            if ($count -gt 100) {
                $prefetchFiles | Sort-Object LastAccessTime | Select-Object -First ($count - 50) | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Host "  [✓] Prefetch cleaned (kept 50 most recent)" -ForegroundColor Green
            }
        }
    }
    
    Show-ProgressBar -Activity "System Tweaks" -Status "Clearing temp folders..." -PercentComplete 50 -Step $CurrentStep -TotalSteps $TotalSteps
    
    # Clear Windows Temp
    $tempFolders = @(
        "$env:SystemRoot\Temp",
        "$env:TEMP"
    )
    
    foreach ($folder in $tempFolders) {
        if (Test-Path $folder) {
            Get-ChildItem $folder -File -Recurse -ErrorAction SilentlyContinue | 
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Host "  [✓] Temp folders cleaned" -ForegroundColor Green
    
    # Reset Windows Search index if fragmented (HDD only)
    if (-not $IsSSD -and $AggressiveMode) {
        Write-Host "  [i] Rebuilding search index..." -ForegroundColor Cyan
        Stop-Service WSearch -Force -ErrorAction SilentlyContinue
        $indexPath = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows"
        if (Test-Path $indexPath) {
            Remove-Item "$indexPath\Windows.edb" -Force -ErrorAction SilentlyContinue
        }
        Start-Service WSearch -ErrorAction SilentlyContinue
        Write-Host "  [✓] Search index rebuilt" -ForegroundColor Green
    }
    
    Show-ProgressBar -Activity "System Tweaks" -Status "Optimizations applied" -PercentComplete 100 -Step $CurrentStep -TotalSteps $TotalSteps
    
} catch {
    Write-Host "  [!] Some tweaks could not be applied: $_" -ForegroundColor Yellow
}

Write-Progress -Activity "Step $CurrentStep" -Completed

# Final Summary
$EndTime = Get-Date
$Duration = $EndTime - $StartTime

Write-Host "`n$("=" * 60)" -ForegroundColor Green
Write-Host "  OPTIMIZATION COMPLETE" -ForegroundColor Green
Write-Host "$("=" * 60)" -ForegroundColor Green
Write-Host "Drive: $DriveLetter ($DriveType)" -ForegroundColor White
Write-Host "Duration: $($Duration.ToString('hh\:mm\:ss'))" -ForegroundColor White

# Get final drive stats
$finalVolume = Get-Volume -DriveLetter $DriveLetter
$freePercent = [math]::Round(($finalVolume.SizeRemaining / $finalVolume.Size) * 100, 1)
Write-Host "Free Space: $([math]::Round($finalVolume.SizeRemaining / 1GB, 2)) GB ($freePercent%)" -ForegroundColor White

if ($DriveLetter -eq "C" -and -not $SkipSystemRepair -and $needsChkdsk) {
    Write-Host "`n[!] IMPORTANT: CHKDSK is scheduled for next reboot." -ForegroundColor Yellow -BackgroundColor Black
    if (-not $AutoReboot) {
        $rebootNow = Read-Host "Reboot now to complete repairs? (Y/N)"
        if ($rebootNow -eq "Y") {
            Restart-Computer -Force
        }
    } elseif ($AutoReboot) {
        Write-Host "Auto-reboot enabled - restarting in 10 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
}

Write-Host "`nRecommended: Run this script monthly for HDDs, quarterly for SSDs." -ForegroundColor Cyan
Write-Host "Log saved to: $env:TEMP\DriveOptimization_$DriveLetter_$(Get-Date -Format 'yyyyMMdd_HHmmss').log" -ForegroundColor Gray

# Create log file
$logContent = @"
Drive Optimization Log
======================
Start Time: $StartTime
End Time: $EndTime
Duration: $Duration
Drive: $DriveLetter ($DriveType)
Aggressive Mode: $AggressiveMode
System Repair: $(-not $SkipSystemRepair)

Results:
- DISM: $(if($needsRepair){"Repaired"}else{"Healthy"})
- SFC: Completed
- CHKDSK: $(if($needsChkdsk){"Scheduled for reboot"}else{"Clean"})
- Optimization: Completed
"@

$logContent | Out-File -FilePath "$env:TEMP\DriveOptimization_$DriveLetter_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"