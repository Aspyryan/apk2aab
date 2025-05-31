param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,
    
    [Parameter(Mandatory = $true)]
    [string]$ApktoolJarPath,
    
    [Parameter(Mandatory = $true)]
    [string]$Aapt2ExePath,
    
    [Parameter(Mandatory = $true)]
    [string]$AndroidJarPath,
    
    [Parameter(Mandatory = $true)]
    [string]$BundletoolJarPath,
    
    [Parameter(Mandatory = $true)]
    [string]$KeystorePath,
    
    # [Parameter(Mandatory = $true)]
    # [string]$KeystorePassword,
    
    # [Parameter(Mandatory = $true)]
    # [string]$KeyPassword,
    
    [Parameter(Mandatory = $true)]
    [string]$KeyAlias,
    
    [Parameter(Mandatory = $false)]
    [int]$VersionCode = 4,
    
    [Parameter(Mandatory = $false)]
    [string]$VersionName = "1.0",
    
    [Parameter(Mandatory = $false)]
    [int]$MinSdkVersion = 31,
    
    [Parameter(Mandatory = $false)]
    [int]$TargetSdkVersion = 35,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory = $true)]
    [string]$PackageName
)

# Global variables
$script:DecompileDir = "decompile_apk"
$script:BaseDir = "base"
$script:ApkName = [System.IO.Path]::GetFileNameWithoutExtension($ApkPath)

#region Color Output Functions
function Write-Success { param($Message) Write-Host $Message -ForegroundColor Green }
function Write-Info { param($Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host $Message -ForegroundColor Red }
function Write-Step { param($StepNumber, $Message) Write-Host "`n$StepNumber. $Message" -ForegroundColor Magenta }
#endregion

#region Validation Functions
function Test-FileExists {
    param($Path, $Description)
    if (-not (Test-Path $Path)) {
        Write-Error "ERROR: $Description not found at: $Path"
        return $false
    }
    Write-Success "✓ Found $Description at: $Path"
    return $true
}

function Test-AllRequiredFiles {
    Write-Step "1" "Validating required files"
    
    $validationResults = @(
        (Test-FileExists $ApkPath "APK file"),
        (Test-FileExists $ApktoolJarPath "Apktool JAR"),
        (Test-FileExists $Aapt2ExePath "AAPT2 executable"),
        (Test-FileExists $AndroidJarPath "Android JAR"),
        (Test-FileExists $BundletoolJarPath "Bundletool JAR"),
        (Test-FileExists $KeystorePath "Keystore")
    )
    
    if ($validationResults -contains $false) {
        Write-Error "One or more required files are missing. Exiting..."
        exit 1
    }
    
    Write-Success "✓ All required files validated successfully"
}
#endregion

#region Cleanup Functions
function Remove-TempDirectories {
    Write-Step "2" "Cleaning up temporary directories"
    
    $tempItems = @("decompile_apk", "base", "res.zip", "base.zip", "base_final.zip", "unsigned.aab")
    
    foreach ($item in $tempItems) {
        if (Test-Path $item) {
            Write-Info "Removing $item..."
            Remove-Item $item -Recurse -Force
        }
    }
    
    Write-Success "✓ Temporary directories cleaned"
}

function Remove-FinalTempFiles {
    Write-Info "Cleaning up final temporary files..."
    
    $tempFiles = @("res.zip", "base.zip", "base_final.zip", "unsigned.aab")
    
    foreach ($file in $tempFiles) {
        if (Test-Path $file) {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            Write-Info "Removed $file"
        }
    }
}
#endregion

#region APK Processing Functions
function Invoke-ApkDecompilation {
    Write-Step "3" "Decompiling APK"
    
    $decompileCmd = "java -jar `"$ApktoolJarPath`" d `"$ApkPath`" -o $script:DecompileDir -f -s"
    Write-Info "Executing: $decompileCmd"
    
    $result = cmd /c $decompileCmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to decompile APK"
        Write-Error $result
        exit 1
    }
    
    Write-Success "✓ APK decompiled successfully"
}

function Edit-AndroidManifest {
    Write-Step "4" "Editing AndroidManifest.xml"
    
    $manifestPath = "$script:DecompileDir\AndroidManifest.xml"
    if (-not (Test-Path $manifestPath)) {
        Write-Error "AndroidManifest.xml not found in decompiled APK"
        exit 1
    }

    # Read the manifest
    $manifest = Get-Content $manifestPath -Raw

    # Remove com.android.vending.derived.apk.id meta-data
    Write-Info "Removing com.android.vending.derived.apk.id meta-data..."
    $manifest = $manifest -replace '<meta-data\s+android:name="com\.android\.vending\.derived\.apk\.id"[^>]*/?>', ''

    # Add Car permissions
    Write-Info "Adding Car permissions..."
    $carPermissions = @"
    <uses-permission android:name="android.car.permission.CAR_UX_RESTRICTIONS_CONFIGURATION"/>
    <uses-permission android:name="android.car.permission.CAR_DRIVING_STATE"/>
"@

    # Find the right place to insert permissions
    if ($manifest -match '(<uses-permission[^>]*>)') {
        $manifest = $manifest -replace '((<uses-permission[^>]*>\s*)+)', "`$1$carPermissions`n    "
    }
    elseif ($manifest -match '(<application)') {
        $manifest = $manifest -replace '(<application)', "$carPermissions`n    `$1"
    }

    # Add distractionOptimized to activities
    Write-Info "Adding distractionOptimized meta-data to activities..."
    $distractionMetaData = '<meta-data android:name="distractionOptimized" android:value="true"/>'
    $manifest = $manifest -replace '(<activity[^>]*>)', "`$1`n            $distractionMetaData"

    # Update package name
    Write-Info "Updating package name to: $script:PackageName"
    $manifest = $manifest -replace 'package="[^"]+"', "package=`"$script:PackageName`""
    

    # Save the modified manifest
    $manifest | Set-Content $manifestPath -Encoding UTF8
    Write-Success "✓ AndroidManifest.xml updated successfully"
}
#endregion

#region Resource Processing Functions
function Fix-PrivateResourceReferences {
    param($ErrorOutput)

    Write-Info "Analyzing resource errors and fixing private references..."

    # Extract file paths and resource names from error messages
    $errorPattern = '([^:]+):(\d+):\s*error:\s*resource\s+android:([^\s]+)\s+is\s+private'
    $matches = [regex]::Matches($ErrorOutput, $errorPattern)

    $fixedFiles = @{}

    foreach ($match in $matches) {
        $filePath = $match.Groups[1].Value
        $lineNumber = $match.Groups[2].Value
        $resourceName = $match.Groups[3].Value

        Write-Info "Found private resource error in: $filePath (line $lineNumber) - Resource: android:$resourceName"

        if (Test-Path $filePath) {
            if (-not $fixedFiles.ContainsKey($filePath)) {
                $fixedFiles[$filePath] = $true

                Write-Info "Fixing private resource references in: $filePath"

                # Read file content
                $content = Get-Content $filePath -Raw

                # Replace @android: with @*android: for all android references
                $originalContent = $content
                $content = $content -replace '@android:', '@*android:'

                if ($content -ne $originalContent) {
                    # Save the modified file
                    $content | Set-Content $filePath -Encoding UTF8
                    Write-Success "✓ Fixed private resource references in: $(Split-Path $filePath -Leaf)"
                }
                else {
                    Write-Warning "No @android: references found to fix in: $(Split-Path $filePath -Leaf)"
                }
            }
        }
        else {
            Write-Warning "File not found for fixing: $filePath"
        }
    }

    if ($fixedFiles.Count -eq 0) {
        Write-Warning "No specific files found to fix. Attempting to fix all XML files in res directory..."
        Get-ChildItem "$script:DecompileDir\res" -Recurse -Filter "*.xml" | ForEach-Object {
            $content = Get-Content $_.FullName -Raw
            $originalContent = $content
            $content = $content -replace '@android:', '@*android:'

            if ($content -ne $originalContent) {
                $content | Set-Content $_.FullName -Encoding UTF8
                Write-Info "Fixed references in: $($_.Name)"
            }
        }
    }

    Write-Success "✓ Private resource reference fixes applied"
}

function Invoke-ResourceCompilation {
    Write-Step "5" "Compiling resources with AAPT2"
    
    $compileCmd = "`"$Aapt2ExePath`" compile --dir $script:DecompileDir\res -o res.zip"
    Write-Info "Executing: $compileCmd"
    
    $result = cmd /c $compileCmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to compile resources"
        Write-Error $result
        exit 1
    }
    
    Write-Success "✓ Resources compiled successfully"
}

function Invoke-ResourceLinking {
    Write-Step "6" "Linking resources and creating base.zip"
    
    $retryCount = 0
    $success = $false
    
    while ($retryCount -lt $MaxRetries -and -not $success) {
        Write-Info "Attempt $($retryCount + 1) of $MaxRetries..."
        
        $linkCmd = "`"$Aapt2ExePath`" link --proto-format -o base.zip -I `"$AndroidJarPath`" --manifest .\$script:DecompileDir\AndroidManifest.xml --min-sdk-version $MinSdkVersion --target-sdk-version $TargetSdkVersion --version-code $VersionCode --version-name $VersionName -R res.zip --auto-add-overlay"
        Write-Info "Executing: $linkCmd"
        
        $result = cmd /c $linkCmd 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $success = $true
            Write-Success "✓ Resources linked successfully"
        }
        else {
            Write-Warning "Link attempt $($retryCount + 1) failed"
            Write-Info "Error output: $result"
            
            # Check if it's a private resource error
            if ($result -match "is private") {
                Write-Info "Private resource error detected. Attempting to fix..."
                Fix-PrivateResourceReferences -ErrorOutput $result
                
                # Need to recompile resources after fixing
                Write-Info "Recompiling resources after fixes..."

                # Remove old res.zip if it exists
                if (Test-Path "res.zip") {
                    Remove-Item "res.zip" -Force
                    Write-Info "Removed old res.zip"
                }

                Invoke-ResourceCompilation
                
                $retryCount++
            }
            else {
                Write-Error "Non-private resource error encountered:"
                Write-Error $result
                exit 1
            }
        }
    }
    
    if (-not $success) {
        Write-Error "Failed to link resources after $MaxRetries attempts"
        exit 1
    }
}
#endregion

#region Base Directory Functions
function New-BaseDirectoryStructure {
    Write-Step "7" "Creating base directory structure"

    # Unzip base.zip
    Write-Info "Extracting base.zip..."
    if (-not (Test-Path "base.zip")) {
        Write-Error "base.zip not found. Resource linking may have failed."
        exit 1
    }
    
    Expand-Archive -Path "base.zip" -DestinationPath $script:BaseDir -Force

    # Create required directories
    $baseDirs = @("$script:BaseDir\manifest", "$script:BaseDir\dex", "$script:BaseDir\root")
    foreach ($dir in $baseDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Info "Created directory: $dir"
        }
    }

    Write-Success "✓ Base directory structure created"
}

function Copy-RequiredFiles {
    Write-Info "Copying required files to base directory..."

    # Copy AndroidManifest.xml to manifest/
    Write-Info "Moving AndroidManifest.xml to manifest/..."
    Move-Item "$script:BaseDir\AndroidManifest.xml" "$script:BaseDir\manifest\AndroidManifest.xml" -Force

    # Copy assets folder if it exists
    if (Test-Path "$script:DecompileDir\assets") {
        Write-Info "Copying assets folder..."
        Copy-Item "$script:DecompileDir\assets" "$script:BaseDir\" -Recurse -Force
    }
    else {
        Write-Warning "No assets folder found in decompiled APK"
    }

    # Copy lib folder if it exists
    if (Test-Path "$script:DecompileDir\lib") {
        Write-Info "Copying lib folder..."
        Copy-Item "$script:DecompileDir\lib" "$script:BaseDir\" -Recurse -Force
    }
    else {
        Write-Warning "No lib folder found in decompiled APK"
    }

    # Copy unknown folder contents to root/
    if (Test-Path "$script:DecompileDir\unknown") {
        Write-Info "Copying unknown folder contents to root/..."
        Get-ChildItem "$script:DecompileDir\unknown" | Copy-Item -Destination "$script:BaseDir\root\" -Recurse -Force
    }
    else {
        Write-Warning "No unknown folder found in decompiled APK"
    }

    # Copy .dex files to dex/
    Write-Info "Copying .dex files to dex/..."
    $dexFiles = Get-ChildItem "$script:DecompileDir\*.dex"
    if ($dexFiles.Count -eq 0) {
        Write-Warning "No .dex files found in decompiled APK"
    }
    else {
        foreach ($dexFile in $dexFiles) {
            Copy-Item $dexFile.FullName "$script:BaseDir\dex\" -Force
            Write-Info "Copied $($dexFile.Name)"
        }
    }

    Write-Success "✓ All required files copied to base directory"
}
#endregion

#region Bundle Creation Functions
function New-FinalBaseZip {
    Write-Step "8" "Creating final base.zip"
    
    Push-Location $script:BaseDir
    
    # List all items to include in the zip
    $itemsToZip = @("manifest", "dex", "res", "resources.pb")
    
    # Add optional items if they exist
    if (Test-Path "root") { $itemsToZip += "root" }
    if (Test-Path "lib") { $itemsToZip += "lib" }
    if (Test-Path "assets") { $itemsToZip += "assets" }
    
    $zipItems = $itemsToZip -join " "
    $zipCmd = "jar cMf ..\base_final.zip $zipItems"
    Write-Info "Executing: $zipCmd"
    
    $result = cmd /c $zipCmd 2>&1
    Pop-Location

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create final base.zip"
        Write-Error $result
        exit 1
    }
    
    Write-Success "✓ Final base.zip created"
}

function New-AabFile {
    Write-Step "9" "Creating AAB file"
    
    $bundleCmd = "java -jar `"$BundletoolJarPath`" build-bundle --modules=base_final.zip --output=unsigned.aab"
    Write-Info "Executing: $bundleCmd"
    
    $result = cmd /c $bundleCmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create AAB file"
        Write-Error $result
        exit 1
    }
    
    Write-Success "✓ Unsigned AAB file created"
}

function Invoke-AabSigning {
    Write-Step "10" "Signing the AAB file"
    
    $signedAabName = "$script:ApkName-signed.aab"

    # Copy unsigned.aab to final name
    Copy-Item "unsigned.aab" $signedAabName -Force

    $signCmd = "jarsigner -verbose -keystore `"$KeystorePath`" -signedjar `"$signedAabName`" `"$signedAabName`" $KeyAlias"
    # $signCmd = "jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 -keystore `"$KeystorePath`" -storepass $KeystorePassword -keypass $KeyPassword `"$signedAabName`" $KeyAlias"
    Write-Info "Executing signing command..."
    Write-Info "Enter keystore password: "
    
    $result = cmd /c $signCmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to sign AAB file"
        Write-Error $result
        exit 1
    }
    
    Write-Success "✓ AAB file signed successfully"
    return $signedAabName
}
#endregion

#region Main Execution Functions
function Show-CompletionSummary {
    param($OutputFile)
    
    Write-Success "`n=== CONVERSION COMPLETED SUCCESSFULLY ==="
    Write-Success "Output file: $OutputFile"
    Write-Info "File size: $([math]::Round((Get-Item $OutputFile).Length / 1MB, 2)) MB"
    Write-Info "You can now upload this AAB file to the Google Play Console."

    # Display final directory contents
    Write-Info "`nFinal directory contents:"
    Get-ChildItem -Name | Where-Object { 
        $_ -like "*.aab" -or $_ -eq $script:DecompileDir -or $_ -eq $script:BaseDir 
    } | ForEach-Object {
        if ($_ -like "*.aab") {
            $size = [math]::Round((Get-Item $_).Length / 1MB, 2)
            Write-Info "  $_ ($size MB)"
        }
        else {
            Write-Info "  $_ (directory)"
        }
    }
}

function Start-ConversionProcess {
    Write-Info "=== APK to AAB Converter Script ==="
    Write-Info "Starting conversion process for: $ApkPath"
    Write-Info "Target output: $script:ApkName-signed.aab"
    
    # Execute all steps in sequence
    Test-AllRequiredFiles
    Remove-TempDirectories
    Invoke-ApkDecompilation
    Edit-AndroidManifest
    Invoke-ResourceCompilation
    Invoke-ResourceLinking
    New-BaseDirectoryStructure
    Copy-RequiredFiles
    New-FinalBaseZip
    New-AabFile
    $outputFile = Invoke-AabSigning
    Remove-FinalTempFiles
    Show-CompletionSummary -OutputFile $outputFile
}
#endregion

# Main execution
try {
    Start-ConversionProcess
}
catch {
    Write-Error "An unexpected error occurred: $_"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}