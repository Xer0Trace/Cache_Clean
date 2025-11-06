# === Windows Deep Cleanup (safe targets only) ===
# Run in an elevated PowerShell window (Administrator)

$ErrorActionPreference = 'Continue'

function Clear-Path {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (Test-Path -Path $Path) {
        try {
            Get-ChildItem -Path $Path -Force -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        } catch {}
    }
}

function Get-FolderSizeBytes {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        (Get-ChildItem -LiteralPath $Path -Force -File -Recurse -ErrorAction SilentlyContinue |
            Measure-Object -Sum Length).Sum
    } catch { 0 }
}

function Show-SummaryBox {
    param([double]$StartGB,[double]$GainedGB,[double]$EndGB,[string]$Profiles)
    $sentence = "You started with $StartGB GB, you gained $GainedGB GB, for a total of $EndGB GB."
    $title = "Cleanup Summary"
    $width = [Math]::Max($sentence.Length, $title.Length) + 6
    $h = "-" * ($width - 2)
    $top = "+" + $h + "+"
    $bottom = "+" + $h + "+"

    function CenterLine($text, $width) {
        $inner = $width - 2
        $pad = [Math]::Max(0, $inner - $text.Length)
        $left = [Math]::Floor($pad / 2)
        $right = $pad - $left
        "|" + (" " * $left) + $text + (" " * $right) + "|"
    }

    Write-Host ""
    Write-Host $top
    Write-Host (CenterLine $title $width)
    Write-Host ("|" + (" " * ($width - 2)) + "|")
    Write-Host (CenterLine $sentence $width)
    Write-Host $bottom
    Write-Host ""
    Write-Host $Profiles
}

$driveLetter = ($env:SystemDrive -replace ':$','')
$before = (Get-PSDrive $driveLetter).Free

$services = @('wuauserv','bits')
foreach ($svc in $services) { try { Stop-Service $svc -Force -ErrorAction SilentlyContinue } catch {} }

Clear-Path "C:\Windows\Temp"
Clear-Path "C:\Windows\Prefetch"
Clear-Path "C:\Windows\SoftwareDistribution\Download"
Clear-Path "C:\Windows\Logs\CBS"
try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}

$profiles = Get-ChildItem 'C:\Users' -Directory -Force |
            Where-Object { $_.Name -notmatch '^(Default|All Users|Default User|Public)$' }

foreach ($p in $profiles) {
    $u = $p.FullName
    Clear-Path "$u\AppData\Local\Temp"
    Clear-Path "$u\AppData\Local\Google\Chrome\User Data\*\Cache"
    Clear-Path "$u\AppData\Local\Microsoft\Edge\User Data\*\Cache"
    Clear-Path "$u\AppData\Local\Mozilla\Firefox\Profiles\*\cache2"
    Clear-Path "$u\AppData\Roaming\Microsoft\Teams\Cache"
    Clear-Path "$u\AppData\Roaming\Zoom\data"
    Clear-Path "$u\Downloads\*.tmp"
}

try { & dism.exe /Online /Cleanup-Image /StartComponentCleanup } catch {}

$after = (Get-PSDrive $driveLetter).Free
$startGB  = [math]::Round($before / 1GB, 2)
$endGB    = [math]::Round($after  / 1GB, 2)
$gainedGB = [math]::Round($endGB - $startGB, 2)

foreach ($svc in $services) { try { Start-Service $svc -ErrorAction SilentlyContinue } catch {} }

$profileSizes = foreach ($p in $profiles) {
    try {
        $bytes = (Get-ChildItem -LiteralPath $p.FullName -Force -File -Recurse -ErrorAction SilentlyContinue |
                  Measure-Object -Sum Length).Sum
        [pscustomobject]@{ Profile = $p.Name; SizeGB = [math]::Round(($bytes / 1GB), 2); Path = $p.FullName }
    } catch {
        [pscustomobject]@{ Profile = $p.Name; SizeGB = 0; Path = $p.FullName }
    }
}

$ProfileTable = $profileSizes |
    Sort-Object SizeGB -Descending |
    Format-Table -AutoSize Profile, SizeGB, Path |
    Out-String -Width 4096

# Single clean output with both the summary and profiles printed together
Show-SummaryBox -StartGB $startGB -GainedGB $gainedGB -EndGB $endGB -Profiles $ProfileTable
