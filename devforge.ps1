# DevForge.io Universal Diagnostic Engine for Windows

$WorkDir = "$env:TEMP\devforge_$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
Set-Location $WorkDir

$TemplateFile = "$WorkDir\template.html"
$OutputHtml   = "$WorkDir\report.html"
$OutputPdf    = "$WorkDir\DevForge_Diagnostic_Report.pdf"

# Hotspot Configuration
$HotspotSSID = "CALIGO_HOST"
$HotspotPass = "Cassidy180209"
$ServerPort  = 8080

# Github Raw URL for remote template fetching
$GithubTemplateUrl = "https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/devforge-toolkit/main/template.html"

# 1. Display Banner
Clear-Host
Write-Host "  ____  _______     _______ ___  ____   ____ _____" -ForegroundColor Yellow
Write-Host " |  _ \| ____\ \   / /  ___/ _ \|  _ \ / ___| ____|" -ForegroundColor Yellow
Write-Host " | | | |  _|  \ \ / /| |_ | | | | |_) | |  _|  _|  " -ForegroundColor Yellow
Write-Host " | |_| | |___  \ V / |  _|| |_| |  _ <| |_| | |___ " -ForegroundColor Yellow
Write-Host " |____/|_____|  \_/  |_|   \___/|_| \_\\____|_____|" -ForegroundColor Yellow
Write-Host "                  _  ___  " -ForegroundColor White
Write-Host "                 (_)/ _ \ " -ForegroundColor White
Write-Host "                 | | | | |" -ForegroundColor White
Write-Host "                 | | |_| |" -ForegroundColor White
Write-Host "                 |_|\___/ " -ForegroundColor White
Write-Host "               === HARDWARE & SOFTWARE DIAGNOSTICS ===" -ForegroundColor Yellow
Write-Host ""

# 2. Retrieve Template
if (Test-Path ".\template.html") {
    Copy-Item ".\template.html" $TemplateFile
} else {
    Write-Host "[*] Fetching DevForge template from web..."
    try {
        Invoke-WebRequest -Uri $GithubTemplateUrl -OutFile $TemplateFile -UseBasicParsing
    } catch {
        Write-Host "[!] Failed to fetch template. Ensure template.html is present." -ForegroundColor Red
        Exit
    }
}

# 3. Gather Diagnostics
$DateStr = (Get-Date).ToString("F")

# Hardware Diagnostics
$Cpu = Get-CimInstance Win32_Processor | Select-Object -ExpandProperty Name
$Os = Get-CimInstance Win32_OperatingSystem
$TotalRam = [math]::Round($Os.TotalVisibleMemorySize / 1MB, 2)
$FreeRam  = [math]::Round($Os.FreePhysicalMemory / 1MB, 2)
$Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    "$($_.DeviceID) Free: $([math]::Round($_.FreeSpace/1GB, 2)) GB / Total: $([math]::Round($_.Size/1GB, 2)) GB"
}

$HardwareLog = "--- CPU --`n$Cpu`n`n--- Memory Usage --`nFree RAM: $FreeRam GB / Total: $TotalRam GB`n`n--- Disks --`n" + ($Disks -join "`n")

# Software Diagnostics
$SoftwareLog = ""
$SystemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$PercentFree = ($SystemDrive.FreeSpace / $SystemDrive.Size) * 100

if ($PercentFree -lt 10) {
    $SoftwareLog += "[CRITICAL] Low Disk Space on C: ($([math]::Round($PercentFree, 2))% free).`n"
    $SoftwareLog += "[SOLUTION] Run Disk Cleanup (cleanmgr.exe) or clear temporary files.`n`n"
} else {
    $SoftwareLog += "[OK] System Drive (C:) storage space is healthy.`n`n"
}

$StoppedServices = Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }
if ($StoppedServices) {
    $SoftwareLog += "[WARNING] Automatic Services Not Running:`n"
    foreach ($svc in $StoppedServices) {
        $SoftwareLog += " - $($svc.Name) ($($svc.DisplayName))`n"
    }
    $SoftwareLog += "[SOLUTION] Start services via Services Management console (services.msc).`n"
} else {
    $SoftwareLog += "[OK] All essential automatic services are running."
}

# 4. Inject Data into Template
$HtmlContent = Get-Content $TemplateFile -Raw
$HtmlContent = $HtmlContent.Replace('{{DATE}}', $DateStr)
$HtmlContent = $HtmlContent.Replace('{{HARDWARE_LOG}}', $HardwareLog)
$HtmlContent = $HtmlContent.Replace('{{SOFTWARE_LOG}}', $SoftwareLog)
Set-Content -Path $OutputHtml -Value $HtmlContent

# 5. Compile PDF via Edge Headless
Write-Host "[*] Compiling PDF Report..."
$EdgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $EdgePath)) {
    $EdgePath = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
}

if (Test-Path $EdgePath) {
    Start-Process -FilePath $EdgePath -ArgumentList "--headless", "--disable-gpu", "--print-to-pdf=`"$OutputPdf`"", "`"$OutputHtml`"" -Wait
    Write-Host "[✓] PDF Report generated at $OutputPdf"
} else {
    Write-Host "[!] Microsoft Edge not found for PDF rendering." -ForegroundColor Red
}

# 6. Delivery Mechanism
Write-Host "`n[*] Checking Network Connectivity..."
$HasInternet = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet

if ($HasInternet) {
    Write-Host "[+] Active Internet Connection Detected."
    Write-Host "[*] Uploading PDF to temporary file host..."
    try {
        # Using 0x0.st / catbox via multipart form upload (bypasses transfer.sh blocks)
        $Form = @{
            file = Get-Item -Path $OutputPdf
        }
        $UploadResult = Invoke-RestMethod -Uri "https://0x0.st" -Method Post -Form $Form -UserAgent "Mozilla/5.0"
        
        Write-Host "`n=========================================================="
        Write-Host "   ONLINE DELIVERY: SCAN OR USE LINK TO DOWNLOAD PDF      "
        Write-Host "=========================================================="
        Write-Host "Direct Link: $UploadResult`n"
        Exit
    } catch {
        Write-Host "[!] Upload failed. Falling back to Hotspot delivery..."
    }
}

# Fallback Mode: Local Hotspot Connection
Write-Host "[!] Initializing Hotspot Fallback ($HotspotSSID)..."
netsh wlan connect name="$HotspotSSID" 2>$null

Start-Sleep -Seconds 4
$LocalIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -like "192.168.*" }).IPAddress | Select-Object -First 1

if ($LocalIP) {
    $DownloadUrl = "http://${LocalIP}:${ServerPort}/DevForge_Diagnostic_Report.pdf"
    Write-Host "`n=========================================================="
    Write-Host "  HOTSPOT DELIVERY: DOWNLOAD LINK READY                   "
    Write-Host "=========================================================="
    Write-Host "Download Link: $DownloadUrl`n"

    Write-Host "[*] Hosting local file server on port $ServerPort. Press Ctrl+C to terminate."
    
    $Listener = New-Object System.Net.HttpListener
    $Listener.Prefixes.Add("http://*:${ServerPort}/")
    $Listener.Start()
    
    while ($Listener.IsListening) {
        $Context = $Listener.GetContext()
        $Response = $Context.Response
        $PdfBytes = [System.IO.File]::ReadAllBytes($OutputPdf)
        $Response.ContentType = "application/pdf"
        $Response.ContentLength64 = $PdfBytes.Length
        $Response.OutputStream.Write($PdfBytes, 0, $PdfBytes.Length)
        $Response.Close()
    }
} else {
    Write-Host "[!] Could not obtain local IP address. Report saved at: $OutputPdf" -ForegroundColor Red
}
