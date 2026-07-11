#################################################################################
#
#   https://github.com/pawalan/adobe-fonts-liberator
#   kudos to Steven Kalinke <https://github.com/kalaschnik/adobe-fonts-revealer>
#
#################################################################################

$AdobeLiveTypeDir = Join-Path $env:APPDATA "Adobe\CoreSync\plugins\livetype"
$AdobeFontsDirs = "t", "w" | ForEach-Object { Join-Path $AdobeLiveTypeDir $_ }
$DestinationDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "Adobe Fonts"

# Change this path if MiKTeX is installed somewhere else.
$Binary = Join-Path $env:LOCALAPPDATA "Programs\MiKTeX\miktex\bin\x64\miktex-otfinfo.exe"

$FontExtensions = @{
    "4F-54-54-4F" = "otf" # OTTO
    "00-01-00-00" = "ttf" # TrueType/OpenType
}

function Get-FontExtension {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $buffer = [byte[]]::new(4)
    $stream = $null

    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )

        if ($stream.Read($buffer, 0, 4) -lt 4) {
            return $null
        }

        $FontExtensions[[System.BitConverter]::ToString($buffer)]
    }
    catch {
        $null
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

Clear-Host

Write-Output "`nLiberating Adobe Fonts"
Write-Output "From:`t$AdobeLiveTypeDir"
Write-Output "To:`t$DestinationDir"
Write-Output "Using:`t$Binary`n"

if (-not (Test-Path -LiteralPath $Binary)) {
    Write-Error "miktex-otfinfo.exe was not found:`n$Binary"
    exit 1
}

& $Binary --version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "miktex-otfinfo.exe could not be started."
    exit 1
}

if (Test-Path -LiteralPath $DestinationDir) {
    $existingItem = Get-ChildItem -LiteralPath $DestinationDir -Force -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -ne $existingItem) {
        Write-Error "Destination directory is not empty, aborting."
        exit 1
    }
}
else {
    New-Item -Path $DestinationDir -ItemType Directory -Force | Out-Null
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

    $sourceFiles = @(Get-ChildItem -LiteralPath $AdobeFontsDir -Force -File -ErrorAction SilentlyContinue)

    Write-Output "`nScanning: $AdobeFontsDir"
    Write-Output "Files found: $($sourceFiles.Count)"

    for ($index = 0; $index -lt $sourceFiles.Count; $index++) {
        $sourceFile = $sourceFiles[$index]
        $filesChecked++

        Write-Progress `
            -Activity "Extracting Adobe Fonts" `
            -Status "$($index + 1) of $($sourceFiles.Count): $($sourceFile.Name)" `
            -PercentComplete ([math]::Round((($index + 1) / $sourceFiles.Count) * 100))

        $fontExtension = Get-FontExtension -Path $sourceFile.FullName
        if ([string]::IsNullOrWhiteSpace($fontExtension)) {
            continue
        }

        $fontName = (& $Binary --postscript-name $sourceFile.FullName 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($fontName)) {
            $failedFonts++
            Write-Warning "Could not read font name: $($sourceFile.Name)"
            continue
        }

        $safeFontName = $fontName.Trim() -replace '[\\/:*?"<>|]', "_"
        $fontFile = Join-Path $DestinationDir "$safeFontName.$fontExtension"

        if (Test-Path -LiteralPath $fontFile) {
            $duplicatesSkipped++
            continue
        }

        try {
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $fontFile -ErrorAction Stop
            $fontsCopied++
            Write-Output "Liberated`t$($sourceFile.Name)`tto`t$safeFontName.$fontExtension"
        }
        catch {
            $failedFonts++
            Write-Warning "Failed to copy: $($sourceFile.FullName)"
        }
    }

    Write-Progress -Activity "Extracting Adobe Fonts" -Completed
}

Write-Output "`nFinished."
Write-Output "Files checked:`t`t$filesChecked"
Write-Output "Fonts copied:`t`t$fontsCopied"
Write-Output "Duplicates skipped:`t$duplicatesSkipped"
Write-Output "Failed fonts:`t`t$failedFonts"
Write-Output "Destination:`t`t$DestinationDir"
Write-Output "`nBye!`n"
