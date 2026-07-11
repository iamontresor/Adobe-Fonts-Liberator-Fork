$Root = Join-Path $env:APPDATA "Adobe\CoreSync\plugins\livetype"

$FontSignatures = @{
    "4F-54-54-4F" = "OTF"   # OTTO
    "00-01-00-00" = "TTF"   # TrueType/OpenType
    "74-72-75-65" = "TTF"   # true
    "74-79-70-31" = "OTF"   # typ1
    "74-74-63-66" = "TTC"   # ttcf
    "77-4F-46-46" = "WOFF"  # wOFF
    "77-4F-46-32" = "WOFF2" # wOF2
}

function Get-FontFormat {
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

        $FontSignatures[[System.BitConverter]::ToString($buffer)]
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

Clear-Host

Write-Output ""
Write-Output "Inspecting Adobe LiveType cache"
Write-Output "Root: $Root"
Write-Output ""

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Error "Adobe LiveType cache directory was not found:`n$Root"
    exit 1
}

$SourceFolders = @(
    Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction Stop
)

if ($SourceFolders.Count -eq 0) {
    Write-Output "No subfolders were found inside the LiveType cache."
    exit 0
}

$Summary = @()
$FilesInspected = 0
$UnreadableFiles = 0

foreach ($Folder in $SourceFolders) {
    $Files = @(
        Get-ChildItem -LiteralPath $Folder.FullName -File -Force -ErrorAction SilentlyContinue
    )

    $Counts = [ordered]@{
        Folder = $Folder.Name
        OTF    = 0
        TTF    = 0
        TTC    = 0
        WOFF   = 0
        WOFF2  = 0
        Total  = 0
    }

    for ($Index = 0; $Index -lt $Files.Count; $Index++) {
        $File = $Files[$Index]
        $FilesInspected++

        Write-Progress `
            -Activity "Inspecting Adobe LiveType cache" `
            -Status "$($Folder.Name): $($Index + 1) of $($Files.Count)" `
            -PercentComplete ([math]::Round((($Index + 1) / $Files.Count) * 100))

        try {
            $FontFormat = Get-FontFormat -Path $File.FullName
        }
        catch {
            $UnreadableFiles++
            continue
        }

        if ($null -eq $FontFormat) {
            continue
        }

        $Counts[$FontFormat]++
        $Counts.Total++
    }

    if ($Counts.Total -gt 0) {
        $Summary += [PSCustomObject]$Counts
    }
}

Write-Progress -Activity "Inspecting Adobe LiveType cache" -Completed

if ($Summary.Count -eq 0) {
    Write-Output "No recognised font files were found."
    Write-Output ""
    Write-Output "Folders inspected: $($SourceFolders.Count)"
    Write-Output "Files inspected:   $FilesInspected"
    Write-Output "Unreadable files:  $UnreadableFiles"
    exit 0
}

Write-Output "Folders containing recognised fonts:"
Write-Output ""

$Summary |
    Sort-Object Folder |
    Format-Table Folder, OTF, TTF, TTC, WOFF, WOFF2, Total -AutoSize

$TotalFonts = ($Summary | Measure-Object -Property Total -Sum).Sum

Write-Output "Folders inspected: $($SourceFolders.Count)"
Write-Output "Files inspected:   $FilesInspected"
Write-Output "Font files found:  $TotalFonts"
Write-Output "Unreadable files:  $UnreadableFiles"
Write-Output ""
