@echo off
del /q app-release.apk 2>nul
flutter build apk --release
echo Waiting for APK file...
:wait_loop
powershell -ExecutionPolicy Bypass -File "C:\Users\Administrator\.gemini\antigravity-cli\premium_notify.ps1" -title "Claude Code" -message "打包完成"
pause
