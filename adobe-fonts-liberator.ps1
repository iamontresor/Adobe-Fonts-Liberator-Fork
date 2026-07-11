﻿#################################################################################
#
#   https://github.com/pawalan/adobe-fonts-liberator
#   kudos to Steven Kalinke <https://github.com/kalaschnik/adobe-fonts-revealer>
#
################################################################################



# Configuration

$AdobeLiveTypeDir = "$env:APPDATA\Adobe\CoreSync\plugins\livetype"

$AdobeFontsDirs = @(
    (Join-Path -Path $AdobeLiveTypeDir -ChildPath "t"),
    (Join-Path -Path $AdobeLiveTypeDir -ChildPath "w")
)

$DesktopDir = [Environment]::GetFolderPath("Desktop")
$DestinationDir = Join-Path -Path $DesktopDir -ChildPath "Adobe Fonts"

# Check for MiKTeX otfinfo.exe in the default installation path #
$Binary = Join-Path `
    -Path $env:LOCALAPPDATA `
    -ChildPath "Programs\MiKTeX\miktex\bin\x64\miktex-otfinfo.exe"
# If you have MiKTeX installed in a different location, change the path above accordingly. #

function Get-FontExtension {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $stream = $null

    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )

        $bytes = New-Object byte[] 4
        $bytesRead = $stream.Read($bytes, 0, 4)

        if ($bytesRead -lt 4) {
            return $null
        }

        $signature = (
            $bytes |
            ForEach-Object { $_.ToString("X2") }
        ) -join "-"

        switch ($signature) {
            "4F-54-54-4F" { return "otf" }
            "00-01-00-00" { return "ttf" }
            default       { return $null }
        }
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}


######################### Script code #########################

Clear-Host

Write-Output "`nLiberating Adobe Fonts"
Write-Output "From:`t$AdobeLiveTypeDir"
Write-Output "To:`t$DestinationDir"
Write-Output "Using:`t$Binary`n"


if (-not (Test-Path -LiteralPath $Binary)) {
    Write-Error "miktex-otfinfo.exe was not found:`n$Binary"
    exit 1
}


# Test whether MiKTeX otfinfo works
& $Binary --version *> $null

if ($LASTEXITCODE -ne 0) {
    Write-Error "miktex-otfinfo.exe could not be started."
    exit 1
}


# Refuse to overwrite an existing non-empty destination
if (Test-Path -LiteralPath $DestinationDir) {
    $existingItem = Get-ChildItem `
        -LiteralPath $DestinationDir `
        -Force `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -ne $existingItem) {
        Write-Error "Destination directory is not empty, aborting."
        exit 1
    }
}
else {
    New-Item `
        -Path $DestinationDir `
        -ItemType Directory `
        -Force |
        Out-Null
}


$filesChecked = 0
$fontsCopied = 0
$duplicatesSkipped = 0
$failedFonts = 0


foreach ($AdobeFontsDir in $AdobeFontsDirs) {

    if (-not (Test-Path -LiteralPath $AdobeFontsDir)) {
        Write-Warning "Source directory not found: $AdobeFontsDir"
        continue
    }

    # Deliberately no -Recurse
    $sourceFiles = @(
        Get-ChildItem `
            -LiteralPath $AdobeFontsDir `
            -Force `
            -File `
            -ErrorAction SilentlyContinue
    )

    Write-Output "`nScanning: $AdobeFontsDir"
    Write-Output "Files found: $($sourceFiles.Count)"

    for ($index = 0; $index -lt $sourceFiles.Count; $index++) {

        $sourceFile = $sourceFiles[$index]
        $filesChecked++

        $percentComplete = [math]::Round(
            (($index + 1) / $sourceFiles.Count) * 100
        )

        Write-Progress `
            -Activity "Extracting Adobe Fonts" `
            -Status "$($index + 1) of $($sourceFiles.Count): $($sourceFile.Name)" `
            -PercentComplete $percentComplete

        $fontExtension = Get-FontExtension -Path $sourceFile.FullName

        if ([string]::IsNullOrWhiteSpace($fontExtension)) {
            continue
        }

        $fontNameOutput = & $Binary `
            --postscript-name `
            $sourceFile.FullName `
            2>$null

        if ($LASTEXITCODE -ne 0 -or $null -eq $fontNameOutput) {
            $failedFonts++
            Write-Warning "Could not read font name: $($sourceFile.Name)"
            continue
        }

        $fontName = (
            $fontNameOutput |
            Select-Object -First 1
        ).ToString().Trim()

        if ([string]::IsNullOrWhiteSpace($fontName)) {
            $failedFonts++
            continue
        }

        # Remove characters Windows does not permit in filenames
        $safeFontName = $fontName -replace '[\\/:*?"<>|]', "_"

        $fontFile = Join-Path `
            -Path $DestinationDir `
            -ChildPath "$safeFontName.$fontExtension"

        if (Test-Path -LiteralPath $fontFile) {
            $duplicatesSkipped++
            continue
        }

        try {
            Copy-Item `
                -LiteralPath $sourceFile.FullName `
                -Destination $fontFile `
                -ErrorAction Stop

            $fontsCopied++

            Write-Output "Liberated`t$($sourceFile.Name)`tto`t$safeFontName.$fontExtension"
        }
        catch {
            $failedFonts++
            Write-Warning "Failed to copy: $($sourceFile.FullName)"
        }
    }

    Write-Progress `
        -Activity "Extracting Adobe Fonts" `
        -Completed
}


Write-Output "`nFinished."
Write-Output "Files checked:`t`t$filesChecked"
Write-Output "Fonts copied:`t`t$fontsCopied"
Write-Output "Duplicates skipped:`t$duplicatesSkipped"
Write-Output "Failed fonts:`t`t$failedFonts"
Write-Output "Destination:`t`t$DestinationDir"
Write-Output "`nBye!`n"