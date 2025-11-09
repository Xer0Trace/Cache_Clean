# === Windows Deep Cleanup (safe targets only) ===
# Run in an elevated PowerShell window (Administrator)
# Executes automatically when pasted or run.
# If you paste this into the console, press Enter once after the paste to start it.

& {
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

    # Capture free space before cleanup
    $driveLetter = ($env:SystemDrive -replace ':$','')
    $before = (Get-PSDrive $driveLetter).Free

    # Stop common update services to allow cleanup
    $services = @('wuauserv','bits')
    foreach ($svc in $services) { try { Stop-Service $svc -Force -ErrorAction SilentlyContinue } catch {} }

    # System cleanup
    Clear-Path "C:\Windows\Temp"
    Clear-Path "C:\Windows\Prefetch"
    Clear-Path "C:\Windows\SoftwareDistribution\Download"
    Clear-Path "C:\Windows\Logs\CBS"
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}

    # User profile cleanup
    $profiles = Get-ChildItem 'C:\Users' -Directory -Force |
                Where-Object { $_.Name -notmatch '^(Default|All Users|Default User|Public)$' }

    foreach ($p in $profiles) {
        $u = $p.FullName

        # Local temp
        Clear-Path "$u\AppData\Local\Temp"

        # Browsers
        # Chrome
        Clear-Path "$u\AppData\Local\Google\Chrome\User Data\*\Cache"
        Clear-Path "$u\AppData\Local\Google\Chrome\User Data\*\Code Cache"
        Clear-Path "$u\AppData\Local\Google\Chrome\User Data\*\GPUCache"

        # Edge
        Clear-Path "$u\AppData\Local\Microsoft\Edge\User Data\*\Cache"
        Clear-Path "$u\AppData\Local\Microsoft\Edge\User Data\*\Code Cache"
        Clear-Path "$u\AppData\Local\Microsoft\Edge\User Data\*\GPUCache"

        # Firefox
        Clear-Path "$u\AppData\Local\Mozilla\Firefox\Profiles\*\cache2"

        # Teams and Zoom
        Clear-Path "$u\AppData\Roaming\Microsoft\Teams\Cache"
        Clear-Path "$u\AppData\Roaming\Microsoft\Teams\Code Cache"
        Clear-Path "$u\AppData\Roaming\Microsoft\Teams\GPUCache"
        Clear-Path "$u\AppData\Roaming\Zoom\data"
        Clear-Path "$u\AppData\Roaming\Zoom\bin\cef\Cache"
        Clear-Path "$u\AppData\Roaming\Zoom\logs"

        # Common app installers and leftover crash dumps
        Clear-Path "$u\Downloads\*.tmp"
        Clear-Path "$u\Downloads\*.log"
        Clear-Path "$u\Documents\*.dmp"
    }

    # Component cleanup using explicit DISM path (fixes command precedence warning)
    try { & "$env:SystemRoot\System32\dism.exe" /Online /Cleanup-Image /StartComponentCleanup } catch {}

    # Calculate disk gain
    $after = (Get-PSDrive $driveLetter).Free
    $startGB  = [math]::Round($before / 1GB, 2)
    $endGB    = [math]::Round($after  / 1GB, 2)
    $gainedGB = [math]::Round($endGB - $startGB, 2)

    # Restart services
    foreach ($svc in $services) { try { Start-Service $svc -ErrorAction SilentlyContinue } catch {} }

    # Gather profile sizes
    $profileSizes = foreach ($p in $profiles) {
        try {
            $bytes = (Get-ChildItem -LiteralPath $p.FullName -Force -File -Recurse -ErrorAction SilentlyContinue |
                      Measure-Object -Sum Length).Sum
            [pscustomobject]@{ Profile = $p.Name; SizeGB = [math]::Round(($bytes / 1GB), 2); Path = $p.FullName }
        } catch {
            [pscustomobject]@{ Profile = $p.Name; SizeGB = 0; Path = $p.FullName }
        }
    }

    # Create formatted table
    $ProfileTable = $profileSizes |
        Sort-Object SizeGB -Descending |
        Format-Table -AutoSize Profile, SizeGB, Path |
        Out-String -Width 4096

    # Auto print summary and table
    Show-SummaryBox -StartGB $startGB -GainedGB $gainedGB -EndGB $endGB -Profiles $ProfileTable
}
