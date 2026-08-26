@echo off
setlocal
cd /d "%~dp0\.."
if "%GODOT_BIN%"=="" set GODOT_BIN=godot.exe
if not exist build\android mkdir build\android
"%GODOT_BIN%" --headless --path "%CD%" --editor --quit-after 2
if errorlevel 1 exit /b %errorlevel%
"%GODOT_BIN%" --headless --path "%CD%" --export-debug "Android YUGITO GC" "build\android\YUGITO_GC_Mobile.apk"
if errorlevel 1 exit /b %errorlevel%
echo APK creee: build\android\YUGITO_GC_Mobile.apk
endlocal
