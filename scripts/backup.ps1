# Configuration
$ProjectName = "crm3v2_copy"
$SourcePath = "C:\flutter\crm3v2 - Copy"
$BackupFolder = "E:\Rynxly_CRM\Rynxly_app_bck"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$ZipFileName = "$($ProjectName)_backup_$($Timestamp).zip"
$ZipPath = Join-Path $BackupFolder $ZipFileName
$ChangelogFile = Join-Path $SourcePath "CHANGELOG.md"

# Ensure backup folder exists
if (!(Test-Path $BackupFolder)) {
    New-Item -ItemType Directory -Path $BackupFolder | Out-Null
    Write-Host "Created backup folder: $BackupFolder" -ForegroundColor Cyan
}

# 1. Prompt for Change Log
Write-Host "--- Backup & Documentation System ---" -ForegroundColor Green
$ChangeDescription = Read-Host "Enter change details for this build (Changelog)"

if ([string]::IsNullOrWhiteSpace($ChangeDescription)) {
    $ChangeDescription = "Minor updates and build."
}

# 2. Update CHANGELOG.md
$DateStr = Get-Date -Format "yyyy-MM-dd HH:mm"
$ChangelogEntry = "`n## [$DateStr]`n- $ChangeDescription`n"

if (!(Test-Path $ChangelogFile)) {
    "# Project Changelog`n" + $ChangelogEntry | Out-File $ChangelogFile -Encoding utf8
} else {
    $CurrentContent = Get-Content $ChangelogFile -Raw
    $NewContent = "# Project Changelog`n" + $ChangelogEntry + ($CurrentContent -replace "# Project Changelog", "")
    $NewContent | Out-File $ChangelogFile -Encoding utf8
}

Write-Host "Updated CHANGELOG.md" -ForegroundColor Yellow

# 3. Zip the project (Excluding build artifacts)
Write-Host "Creating backup zip: $ZipFileName..." -ForegroundColor Cyan

# Define exclusions
$Exclusions = @("build", ".dart_tool", ".git", ".idea", "android/.gradle", "android/app/build", "ios/Pods", "*.zip")

# We use a temporary filter to get files for zipping
$FilesToZip = Get-ChildItem -Path $SourcePath -Recurse | Where-Object {
    $FilePath = $_.FullName
    $IsExcluded = $false
    foreach ($Exclude in $Exclusions) {
        if ($FilePath -like "*\$Exclude*" -or $FilePath -like "*\$Exclude") {
            $IsExcluded = $true
            break
        }
    }
    !$IsExcluded
}

# Compress-Archive is slow for many files, but works without external tools
# Using a temp folder for cleaner zipping
$TempZipSource = Join-Path $env:TEMP "backup_temp_$Timestamp"
if (Test-Path $TempZipSource) { Remove-Item -Recurse -Force $TempZipSource }
New-Item -ItemType Directory -Path $TempZipSource | Out-Null

# Copy only needed files to temp
foreach ($File in $FilesToZip) {
    if (!$File.PSIsContainer) {
        $RelativePath = $File.FullName.Substring($SourcePath.Length + 1)
        $DestFile = Join-Path $TempZipSource $RelativePath
        $DestDir = Split-Path $DestFile
        if (!(Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir | Out-Null }
        Copy-Item $File.FullName $DestFile
    }
}

Compress-Archive -Path "$TempZipSource\*" -DestinationPath $ZipPath -Force

# Cleanup
Remove-Item -Recurse -Force $TempZipSource

Write-Host "Backup saved successfully to: $ZipPath" -ForegroundColor Green
Write-Host "------------------------------------"
