<#
  snap-memories-sorter-windows.ps1 — Rebuild Snapchat memories into two sorted archives (Windows).

  What it does:
    1. Asks you (via native folder-browser dialogs) to pick:
         - the folder that holds your Snapchat export ZIP files
         - a destination folder for the sorted output
    2. Extracts every *.zip from the chosen folder into a temporary working
       directory (automatically deleted when the script finishes).
    3. For every "<prefix>-main.<ext>" memory it finds:
         - copies the raw file into   <dest>\Originals\<Year>\<Month>\   (untouched)
         - writes the "as seen in Snapchat" version into <dest>\Merged\<Year>\<Month>\
           (overlay burned on top for photos AND videos; plain copy if no overlay)

  Output:  <dest>\{Originals,Merged}\YYYY\MM\

  Requirements:
    - Windows with Windows PowerShell 5.1+ (ships with Windows 10/11)
    - ffmpeg + ffprobe on PATH (ffprobe ships with ffmpeg)
      https://www.gyan.dev/ffmpeg/builds/  or  winget install Gyan.FFmpeg

  Usage:  right-click the file -> "Run with PowerShell"
          or:  powershell -ExecutionPolicy Bypass -File .\snap-memories-sorter-windows.ps1
#>

# ---- settings (rename the two output folders here if you like) -----------
$SubOrig   = 'Originals'    # raw -main files only
$SubMerged = 'Merged'       # overlays composited in

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

# ---- native folder picker ------------------------------------------------
function Select-Folder([string]$Description) {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Description
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

Write-Host 'A dialog will ask for the folder that contains your Snapchat ZIP files...'
$ZipDir = Select-Folder 'Select the folder that contains your Snapchat export ZIP files'
if (-not $ZipDir) { Write-Host 'No source folder selected. Aborting.'; exit 1 }

Write-Host 'Now pick where the sorted memories should be saved...'
$Base = Select-Folder 'Select the destination folder (Originals & Merged are created inside)'
if (-not $Base) { Write-Host 'No destination folder selected. Aborting.'; exit 1 }

$Orig   = Join-Path $Base $SubOrig
$Merged = Join-Path $Base $SubMerged
New-Item -ItemType Directory -Force -Path $Orig, $Merged | Out-Null

# ---- temporary work dir (auto-removed on exit) --------------------------
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("snap-merged-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Mem = Join-Path $Work 'memories'

# ---- locate ffmpeg + ffprobe (ffprobe ships with ffmpeg) ----------------
function Resolve-Tool([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $local = Join-Path $PSScriptRoot "$Name.exe"
    if (Test-Path $local) { return $local }
    return $null
}
$Ffmpeg  = Resolve-Tool 'ffmpeg'
$Ffprobe = Resolve-Tool 'ffprobe'
if (-not $Ffmpeg -or -not $Ffprobe) {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
    Write-Host 'ffmpeg/ffprobe not found. Install ffmpeg (ffprobe is included): winget install Gyan.FFmpeg, then reopen PowerShell.'
    exit 1
}

Write-Host ''
Write-Host "Zips in:  $ZipDir"
Write-Host "Work dir: $Work   (temporary - deleted when done)"
Write-Host "Output:   $Base\{$SubOrig,$SubMerged}\YYYY\MM"
Write-Host "ffmpeg:   $Ffmpeg"
Write-Host ''

# ---- helpers -------------------------------------------------------------
function Find-Overlay([string]$Dir, [string]$Prefix) {
    $hit = Get-ChildItem -LiteralPath $Dir -Filter "$Prefix-overlay.*" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Get-BaseDims([string]$Path) {  # returns @(w, h) or $null
    try {
        $d = & $Ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x $Path 2>$null
        if ($d -match '^(\d+)x(\d+)') { return @($Matches[1], $Matches[2]) }
    } catch { }
    return $null
}

function Remove-Temp([string]$Path) {
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
}

function Set-Stamp([string]$Path, [string]$Year, [string]$Month, [string]$Day) {
    if ($Year -eq 'unknown') { return }
    try {
        $dt = [datetime]::ParseExact("$Year$Month$Day 12:00", 'yyyyMMdd HH:mm', $null)
        (Get-Item -LiteralPath $Path).LastWriteTime = $dt
    } catch { }
}

function Process-One([string]$Main) {
    $dir    = Split-Path $Main -Parent
    $base   = Split-Path $Main -Leaf
    $stem   = [System.IO.Path]::GetFileNameWithoutExtension($base)
    $prefix = $stem -replace '-main$', ''
    $ext    = [System.IO.Path]::GetExtension($base).TrimStart('.')
    $lext   = $ext.ToLower()

    # date lives in the filename as YYYY-MM-DD...; require that exact shape
    if ($base -match '^(\d{4})-(\d{2})-(\d{2})') {
        $year = $Matches[1]; $month = $Matches[2]; $day = $Matches[3]
    } else {
        $year = 'unknown'; $month = '00'; $day = '01'
    }

    $kind = 'image'
    if ($lext -in @('mp4','mov','m4v','avi')) { $kind = 'video' }
    $overlay = Find-Overlay $dir $prefix

    # --- Originals: raw main, untouched ---
    $odir = Join-Path (Join-Path $Orig $year) $month
    New-Item -ItemType Directory -Force -Path $odir | Out-Null
    $oout = Join-Path $odir "$prefix.$lext"
    if (-not (Test-Path -LiteralPath $oout)) {
        try {
            Copy-Item -LiteralPath $Main -Destination $oout -Force
            Set-Stamp $oout $year $month $day
        } catch { Write-Host "[FAIL orig] $prefix" }
    }

    # --- Merged: as seen in Snapchat ---
    $mdir = Join-Path (Join-Path $Merged $year) $month
    New-Item -ItemType Directory -Force -Path $mdir | Out-Null
    # A successful image composite is re-encoded to JPEG; a video keeps its container.
    # If the overlay can't be applied we keep the raw original with ITS OWN extension,
    # so the file's name always matches its real contents.
    $omext = $lext
    if ($kind -eq 'image') { $omext = 'jpg' }
    $moutOk   = Join-Path $mdir "$prefix.$omext"   # written on a successful merge
    $moutOrig = Join-Path $mdir "$prefix.$lext"    # written when keeping the original
    if ((Test-Path -LiteralPath $moutOk) -or (Test-Path -LiteralPath $moutOrig)) { Write-Host "[skip] $prefix"; return }

    if ($overlay) {
        # Scale the overlay to the base's exact pixel size, then composite it on top.
        # The size is read explicitly with ffprobe: scale2ref proved non-deterministic
        # with the WebP overlays Snapchat sometimes ships as .png. No -loop is used,
        # so a corrupt/undecodable overlay just yields no output instead of hanging.
        $tmp = "$moutOk.tmp.$omext"
        $dims = Get-BaseDims $Main
        $merged = $false
        if ($dims) {
            $w = $dims[0]; $h = $dims[1]
            $fc = "[1:v]scale=${w}:${h}[ovl];[0:v][ovl]overlay=0:0[v]"
            try {
                if ($kind -eq 'image') {
                    & $Ffmpeg -nostdin -y -loglevel error -i $Main -i $overlay `
                        -filter_complex $fc -map '[v]' -frames:v 1 -q:v 2 $tmp 2>$null
                } else {
                    & $Ffmpeg -nostdin -y -loglevel error -i $Main -i $overlay `
                        -filter_complex $fc -map '[v]' -map '0:a?' -c:a copy `
                        -movflags +faststart $tmp 2>$null
                }
                $merged = ($LASTEXITCODE -eq 0)
            } catch { $merged = $false }
        }
        if ($merged -and (Test-Path -LiteralPath $tmp) -and (Get-Item -LiteralPath $tmp).Length -gt 0) {
            Move-Item -LiteralPath $tmp -Destination $moutOk -Force
            Set-Stamp $moutOk $year $month $day
            Write-Host "[ok]   $year\$month\$prefix  (overlay merged)"
            return
        }
        # overlay could not be applied — keep the memory anyway (original, no overlay)
        Remove-Temp $tmp
        Write-Host "[warn] $year\$month\$prefix  (overlay unreadable, keeping original)"
    }

    $otmp = "$moutOrig.tmp.$lext"
    try {
        Copy-Item -LiteralPath $Main -Destination $otmp -Force
        Move-Item -LiteralPath $otmp -Destination $moutOrig -Force
        Set-Stamp $moutOrig $year $month $day
        Write-Host "[ok]   $year\$month\$prefix"
    }
    catch {
        Remove-Temp $otmp
        Write-Host "[FAIL copy] $prefix"
    }
}

try {
    # ---- 1. extract all zips from the chosen folder ---------------------
    $zips = Get-ChildItem -LiteralPath $ZipDir -Filter '*.zip' -File
    if (-not $zips) { Write-Host "No .zip files found in $ZipDir."; exit 1 }
    foreach ($z in $zips) {
        Write-Host "extracting $($z.Name) ..."
        Expand-Archive -LiteralPath $z.FullName -DestinationPath $Work -Force
    }
    Write-Host "Extracted $($zips.Count) zip file(s)."
    if (-not (Test-Path -LiteralPath $Mem)) {
        Write-Host "No 'memories' folder found inside the extracted data."; exit 1
    }
    Write-Host ''

    # ---- 2. process every *-main.* memory ------------------------------
    $mains = @(Get-ChildItem -LiteralPath $Mem -Recurse -File -Filter '*-main.*')
    $vids  = @($mains | Where-Object { $_.Extension.ToLower() -in '.mp4', '.mov', '.m4v', '.avi' }).Count
    $imgs  = $mains.Count - $vids
    Write-Host "Found $($mains.Count) memories: $imgs photo(s), $vids video(s)."
    Write-Host 'Processing (videos take longer)...'
    Write-Host ''
    foreach ($m in $mains) { Process-One $m.FullName }

    $oc = @(Get-ChildItem -LiteralPath $Orig   -Recurse -File).Count
    $mc = @(Get-ChildItem -LiteralPath $Merged -Recurse -File).Count
    Write-Host ''
    Write-Host 'Done.'
    Write-Host "  $SubOrig : $oc files   ($Orig)"
    Write-Host "  $SubMerged : $mc files   ($Merged)"
}
finally {
    # always clean up the temporary working directory
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}
