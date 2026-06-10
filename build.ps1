# Set console title
$Host.UI.RawUI.WindowTitle = "Inventory Management System - Android APK Builder"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "         Inventory Management System - Android APK Builder" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] Cleaning project cache (flutter clean)..." -ForegroundColor Yellow
Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
flutter clean

Write-Host ""
Write-Host "[2/3] Fetching project dependencies (flutter pub get)..." -ForegroundColor Yellow
Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
flutter pub get

Write-Host ""
Write-Host "[3/3] Building Android APK (Release version)..." -ForegroundColor Yellow
Write-Host "This process may take 1-3 minutes. Please wait..." -ForegroundColor Gray
Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
flutter build apk --release

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Red
    Write-Host "[ERROR] Android APK Compilation Failed!" -ForegroundColor Red
    Write-Host "Please review the error messages above." -ForegroundColor Red
    Write-Host "=================================================================" -ForegroundColor Red
} else {
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host "[SUCCESS] Android APK Compiled Successfully!" -ForegroundColor Green
    Write-Host "[PATH] APK generated at:" -ForegroundColor Green
    Write-Host "       F:\testCode\hw-uni-app\hw-app-new\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Green
}

Write-Host ""
Read-Host "Press Enter to exit..."
