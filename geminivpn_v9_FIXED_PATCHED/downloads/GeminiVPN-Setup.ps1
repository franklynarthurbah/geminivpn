# GeminiVPN — Windows Setup Script (PowerShell)
# Run as Administrator: Right-click → Run with PowerShell
# Or: powershell -ExecutionPolicy Bypass -File GeminiVPN-Setup.ps1

$Host.UI.RawUI.WindowTitle = "GeminiVPN Windows Setup"
Write-Host ""
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   GeminiVPN — Windows Installer      ║" -ForegroundColor Cyan
Write-Host "║   Powered by WireGuard®              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check admin
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "[!] Please run as Administrator" -ForegroundColor Red
    Write-Host "    Right-click the script → Run as Administrator" -ForegroundColor Yellow
    pause; exit 1
}

Write-Host "[→] Downloading WireGuard for Windows..." -ForegroundColor Cyan
$wgUrl = "https://download.wireguard.com/windows-client/wireguard-installer.exe"
$tmpExe = "$env:TEMP\wireguard-installer.exe"

try {
    Invoke-WebRequest -Uri $wgUrl -OutFile $tmpExe -UseBasicParsing
    Write-Host "[✓] WireGuard downloaded" -ForegroundColor Green
    Write-Host "[→] Installing WireGuard (silent)..." -ForegroundColor Cyan
    Start-Process -FilePath $tmpExe -ArgumentList "/S" -Wait
    Write-Host "[✓] WireGuard installed" -ForegroundColor Green
} catch {
    Write-Host "[!] Auto-download failed. Opening WireGuard website..." -ForegroundColor Yellow
    Start-Process "https://www.wireguard.com/install/"
}

Write-Host ""
Write-Host "═══ NEXT STEPS ═══════════════════════════════════" -ForegroundColor White
Write-Host ""
Write-Host "  1. Open your browser → https://geminivpn.zapto.org" -ForegroundColor Cyan
Write-Host "  2. Log in → Dashboard → Devices → Add Device" -ForegroundColor Cyan
Write-Host "  3. Download your .conf file" -ForegroundColor Cyan
Write-Host "  4. Open WireGuard → Import tunnel from file" -ForegroundColor Cyan
Write-Host "  5. Click Activate" -ForegroundColor Cyan
Write-Host ""
Write-Host "[✓] Setup complete! Visit https://geminivpn.zapto.org" -ForegroundColor Green
Write-Host ""
Start-Process "https://geminivpn.zapto.org"
pause
