$Root = "$env:APPDATA\Adobe\CoreSync\plugins\livetype"


function Get-FontFormat {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Buffer = New-Object byte[] 4
    $Stream = $null

    try {
        $Stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )

        $BytesRead = $Stream.Read($Buffer, 0, 4)

        if ($BytesRead -lt 4) {
            return $null
        }

        $Signature = (
            $Buffer |
            ForEach-Object {
                $_.ToString("X2")
            }
        ) -join "-"

        switch ($Signature) {
            "4F-54-54-4F" { return "OTF"   } # OTTO
            "00-01-00-00" { return "TTF"   } # TrueType/OpenType
            "74-72-75-65" { return "TTF"   } # true
            "74-79-70-31" { return "OTF"   } # typ1
            "74-74-63-66" { return "TTC"   } # ttcf
            "77-4F-46-46" { return "WOFF"  } # wOFF
            "77-4F-46-32" { return "WOFF2" } # wOF2
            default       { return $null   }
        }
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $Stream) {
            $Stream.Dispose()
        }
    }
}


Clear-Host

Write-Output ""
Write-Output "Inspecting Adobe LiveType cache"
Write-Output "Root: $Root"
Write-Output ""


# Confirm that Adobe's LiveType directory exists
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Error "Adobe LiveType cache directory was not found:`n$Root"
    exit 1
}


# Automatically discover all immediate subfolders
$SourceFolders = @(
    Get-ChildItem `
        -LiteralPath $Root `
        -Directory `
        -Force `
        -ErrorAction Stop
)


if ($SourceFolders.Count -eq 0) {
    Write-Output "No subfolders were found inside the LiveType cache."
    exit 0
}


$FontResults = @()
$FilesInspected = 0
$UnreadableFiles = 0


for ($FolderIndex = 0; $FolderIndex -lt $SourceFolders.Count; $FolderIndex++) {

    $Folder = $SourceFolders[$FolderIndex]

    $Files = @(
        Get-ChildItem `
            -LiteralPath $Folder.FullName `
            -File `
            -Force `
            -ErrorAction SilentlyContinue
    )

    for ($FileIndex = 0; $FileIndex -lt $Files.Count; $FileIndex++) {

        $File = $Files[$FileIndex]
        $FilesInspected++

        if ($Files.Count -gt 0) {
            $PercentComplete = [math]::Round(
                (($FileIndex + 1) / $Files.Count) * 100
            )

            Write-Progress `
                -Activity "Inspecting Adobe LiveType cache" `
                -Status "$($Folder.Name): $($FileIndex + 1) of $($Files.Count)" `
                -PercentComplete $PercentComplete
        }

        try {
            $FontFormat = Get-FontFormat -Path $File.FullName

            if ($null -ne $FontFormat) {
                $FontResults += [PSCustomObject]@{
                    Folder   = $Folder.Name
                    Format   = $FontFormat
                    FileName = $File.Name
                    FullPath = $File.FullName
                }
            }
        }
        catch {
            $UnreadableFiles++
        }
    }
}


Write-Progress `
    -Activity "Inspecting Adobe LiveType cache" `
    -Completed


if ($FontResults.Count -eq 0) {
    Write-Output "No recognised font files were found."
    Write-Output ""
    Write-Output "Folders inspected: $($SourceFolders.Count)"
    Write-Output "Files inspected:   $FilesInspected"
    Write-Output "Unreadable files:  $UnreadableFiles"
    exit 0
}


$Summary = @(
    $FontResults |
        Group-Object Folder |
        ForEach-Object {

            $FolderFonts = @($_.Group)

            [PSCustomObject]@{
                Folder = $_.Name
                OTF    = @(
                    $FolderFonts |
                    Where-Object { $_.Format -eq "OTF" }
                ).Count
                TTF    = @(
                    $FolderFonts |
                    Where-Object { $_.Format -eq "TTF" }
                ).Count
                TTC    = @(
                    $FolderFonts |
                    Where-Object { $_.Format -eq "TTC" }
                ).Count
                WOFF   = @(
                    $FolderFonts |
                    Where-Object { $_.Format -eq "WOFF" }
                ).Count
                WOFF2  = @(
                    $FolderFonts |
                    Where-Object { $_.Format -eq "WOFF2" }
                ).Count
                Total  = $FolderFonts.Count
            }
        } |
        Sort-Object Folder
)


Write-Output "Folders containing recognised fonts:"
Write-Output ""

$Summary |
    Format-Table `
        Folder,
        OTF,
        TTF,
        TTC,
        WOFF,
        WOFF2,
        Total `
        -AutoSize


$TotalFonts = (
    $Summary |
    Measure-Object -Property Total -Sum
).Sum


Write-Output "Folders inspected: $($SourceFolders.Count)"
Write-Output "Files inspected:   $FilesInspected"
Write-Output "Font files found:  $TotalFonts"
Write-Output "Unreadable files:  $UnreadableFiles"
Write-Output ""