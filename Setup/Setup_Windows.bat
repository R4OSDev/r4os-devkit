@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem R4OS DevKit setup for 64-bit Windows.
rem Every generated file stays below the DevKit directory.

for %%I in ("%~dp0.") do set "SETUP_DIR=%%~fI"
for %%I in ("!SETUP_DIR!\..") do set "DEVKIT_ROOT=%%~fI"
for %%I in ("!SETUP_DIR!") do set "SETUP_NAME=%%~nxI"
for %%I in ("!DEVKIT_ROOT!") do set "DEVKIT_NAME=%%~nxI"

if /I not "!SETUP_NAME!"=="Setup" (
    echo [ERROR] Setup_Windows.bat must be located in DevKit\Setup.
    exit /b 1
)

if /I not "!DEVKIT_NAME!"=="DevKit" (
    echo [ERROR] The parent directory of Setup must be named DevKit.
    exit /b 1
)

if /I not "%PROCESSOR_ARCHITECTURE%"=="AMD64" if /I not "%PROCESSOR_ARCHITEW6432%"=="AMD64" (
    echo [ERROR] This setup currently supports 64-bit Windows on x86_64 only.
    exit /b 1
)

where curl.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] curl.exe is required but was not found.
    exit /b 1
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Windows PowerShell is required but was not found.
    exit /b 1
)

set "ZIG_VERSION=0.16.0"
set "ZIG_URL=https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip"
set "ZIG_SHA256=68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e"

set "LIMINE_VERSION=12.0.1"
set "LIMINE_URL=https://github.com/Limine-Bootloader/Limine/releases/download/v12.0.1/limine-binary-12.0.1.zip"
set "LIMINE_SHA256=175be9999063b7754af52b2852357f61cbe67a32ad8d3bf0d76d69c8757f9865"

set "QEMU_VERSION=11.0.0"
set "QEMU_URL=https://qemu.weilnetz.de/w64/2026/qemu-w64-setup-20260422.exe"
set "QEMU_SHA512=64a43c0d39acddc9d30d290935a312a2b5c4fa62cffe6c27090f2a45ca6c8de0f0e8673e1e5117fb116a8742f86df92163531afc23f34758aadfc6d82c1f41a5"

rem QEMU is extracted without running its installer. These temporary
rem 7-Zip binaries make that possible without touching the registry.
set "SEVENZIP_VERSION=26.02"
set "SEVENZIP_REDUCED_URL=https://github.com/ip7z/7zip/releases/download/26.02/7zr.exe"
set "SEVENZIP_REDUCED_SHA256=56b8cc9f4971cef253644fafe54063ed7fdca551d4dee0f8c6baa81b855acd72"
set "SEVENZIP_URL=https://github.com/ip7z/7zip/releases/download/26.02/7z2602-x64.exe"
set "SEVENZIP_SHA256=6745fa76dc2ea031596d8678f6f6b99c3c1b435b4164a63485adbbc7b8d82ef0"

set "ZIG_TARGET=!DEVKIT_ROOT!\Toolchains\Zig"
set "LIMINE_TARGET=!DEVKIT_ROOT!\Boot\Limine"
set "QEMU_TARGET=!DEVKIT_ROOT!\Emulation\QEMU"

set "INSTALL_ZIG=1"
set "INSTALL_LIMINE=1"
set "INSTALL_QEMU=1"

call :check_zig
if errorlevel 1 exit /b 1

call :check_limine
if errorlevel 1 exit /b 1

call :check_qemu
if errorlevel 1 exit /b 1

if "!INSTALL_ZIG!!INSTALL_LIMINE!!INSTALL_QEMU!"=="000" (
    echo.
    echo R4OS DevKit is already set up.
    exit /b 0
)

set "TEMP_ROOT=!SETUP_DIR!\.Setup_Windows_!RANDOM!_!RANDOM!"
mkdir "!TEMP_ROOT!" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not create the temporary setup directory.
    exit /b 1
)

if "!INSTALL_ZIG!"=="1" (
    call :install_zig
    if errorlevel 1 goto :failure
)

if "!INSTALL_LIMINE!"=="1" (
    call :install_limine
    if errorlevel 1 goto :failure
)

if "!INSTALL_QEMU!"=="1" (
    call :install_qemu
    if errorlevel 1 goto :failure
)

call :cleanup
if errorlevel 1 exit /b 1
echo.
echo R4OS DevKit setup completed successfully.
exit /b 0

:failure
set "SETUP_EXIT_CODE=!ERRORLEVEL!"
if "!SETUP_EXIT_CODE!"=="0" set "SETUP_EXIT_CODE=1"
call :cleanup
echo.
echo [ERROR] R4OS DevKit setup failed.
exit /b !SETUP_EXIT_CODE!

:check_zig
if not exist "!ZIG_TARGET!\zig.exe" (
    call :require_empty "!ZIG_TARGET!" "Zig"
    exit /b !ERRORLEVEL!
)

call :matches_version "!ZIG_TARGET!\zig.exe" "version" "!ZIG_VERSION!" "exact"
if not errorlevel 1 (
    set "INSTALL_ZIG=0"
    echo [OK] Zig !ZIG_VERSION! is already installed.
    exit /b 0
)

echo [ERROR] !ZIG_TARGET! contains a different Zig version.
exit /b 1

:check_limine
if not exist "!LIMINE_TARGET!\limine-tool-windows-x86\limine.exe" (
    call :require_empty "!LIMINE_TARGET!" "Limine"
    exit /b !ERRORLEVEL!
)

call :matches_version "!LIMINE_TARGET!\limine-tool-windows-x86\limine.exe" "--version" "Limine !LIMINE_VERSION!" "prefix"
if not errorlevel 1 (
    set "INSTALL_LIMINE=0"
    echo [OK] Limine !LIMINE_VERSION! is already installed.
    exit /b 0
)

echo [ERROR] !LIMINE_TARGET! contains a different Limine version.
exit /b 1

:check_qemu
if not exist "!QEMU_TARGET!\qemu-system-x86_64.exe" (
    call :require_empty "!QEMU_TARGET!" "QEMU"
    exit /b !ERRORLEVEL!
)

call :matches_version "!QEMU_TARGET!\qemu-system-x86_64.exe" "--version" "QEMU emulator version !QEMU_VERSION!" "prefix"
if not errorlevel 1 (
    set "INSTALL_QEMU=0"
    echo [OK] QEMU !QEMU_VERSION! is already installed.
    exit /b 0
)

echo [ERROR] !QEMU_TARGET! contains a different QEMU version.
exit /b 1

:require_empty
if not exist "%~1" mkdir "%~1" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not create %~1.
    exit /b 1
)

set "DIRECTORY_HAS_CONTENT="
for /f "delims=" %%F in ('dir /b /a "%~1" 2^>nul') do set "DIRECTORY_HAS_CONTENT=1"
if defined DIRECTORY_HAS_CONTENT (
    echo [ERROR] %~2 target is not empty: %~1
    echo         Empty the directory before running setup again.
    exit /b 1
)
exit /b 0

:install_zig
echo.
echo === Zig !ZIG_VERSION! ===
set "ZIG_ARCHIVE=!TEMP_ROOT!\zig.zip"
set "ZIG_EXTRACT=!TEMP_ROOT!\Zig"

call :download "!ZIG_URL!" "!ZIG_ARCHIVE!" "Zig"
if errorlevel 1 exit /b 1
call :verify_hash "!ZIG_ARCHIVE!" "SHA256" "!ZIG_SHA256!" "Zig"
if errorlevel 1 exit /b 1
call :extract_zip "!ZIG_ARCHIVE!" "!ZIG_EXTRACT!" "Zig"
if errorlevel 1 exit /b 1

set "ZIG_SOURCE=!ZIG_EXTRACT!\zig-x86_64-windows-!ZIG_VERSION!"
if not exist "!ZIG_SOURCE!\zig.exe" (
    echo [ERROR] The Zig archive has an unexpected structure.
    exit /b 1
)

call :matches_version "!ZIG_SOURCE!\zig.exe" "version" "!ZIG_VERSION!" "exact"
if errorlevel 1 (
    echo [ERROR] The extracted Zig version is not !ZIG_VERSION!.
    exit /b 1
)

rmdir "!ZIG_TARGET!" >nul 2>&1
if exist "!ZIG_TARGET!" (
    echo [ERROR] Could not prepare !ZIG_TARGET! for installation.
    exit /b 1
)
move /Y "!ZIG_SOURCE!" "!ZIG_TARGET!" >nul
if errorlevel 1 (
    echo [ERROR] Could not install Zig into !ZIG_TARGET!.
    exit /b 1
)
echo [OK] Zig installed in !ZIG_TARGET!.
exit /b 0

:install_limine
echo.
echo === Limine !LIMINE_VERSION! ===
set "LIMINE_ARCHIVE=!TEMP_ROOT!\limine.zip"
set "LIMINE_EXTRACT=!TEMP_ROOT!\Limine"

call :download "!LIMINE_URL!" "!LIMINE_ARCHIVE!" "Limine"
if errorlevel 1 exit /b 1
call :verify_hash "!LIMINE_ARCHIVE!" "SHA256" "!LIMINE_SHA256!" "Limine"
if errorlevel 1 exit /b 1
call :extract_zip "!LIMINE_ARCHIVE!" "!LIMINE_EXTRACT!" "Limine"
if errorlevel 1 exit /b 1

set "LIMINE_SOURCE=!LIMINE_EXTRACT!\limine-binary-!LIMINE_VERSION!"
if not exist "!LIMINE_SOURCE!\limine-tool-windows-x86\limine.exe" (
    echo [ERROR] The Limine archive has an unexpected structure.
    exit /b 1
)

call :matches_version "!LIMINE_SOURCE!\limine-tool-windows-x86\limine.exe" "--version" "Limine !LIMINE_VERSION!" "prefix"
if errorlevel 1 (
    echo [ERROR] The extracted Limine version is not !LIMINE_VERSION!.
    exit /b 1
)

rmdir "!LIMINE_TARGET!" >nul 2>&1
if exist "!LIMINE_TARGET!" (
    echo [ERROR] Could not prepare !LIMINE_TARGET! for installation.
    exit /b 1
)
move /Y "!LIMINE_SOURCE!" "!LIMINE_TARGET!" >nul
if errorlevel 1 (
    echo [ERROR] Could not install Limine into !LIMINE_TARGET!.
    exit /b 1
)
echo [OK] Limine installed in !LIMINE_TARGET!.
exit /b 0

:install_qemu
echo.
echo === QEMU !QEMU_VERSION! ===
set "QEMU_ARCHIVE=!TEMP_ROOT!\qemu.exe"
set "SEVENZIP_REDUCED=!TEMP_ROOT!\7zr.exe"
set "SEVENZIP_ARCHIVE=!TEMP_ROOT!\7z-x64.exe"
set "SEVENZIP_EXTRACT=!TEMP_ROOT!\SevenZip"
set "QEMU_EXTRACT=!TEMP_ROOT!\QEMU"

call :download "!QEMU_URL!" "!QEMU_ARCHIVE!" "QEMU"
if errorlevel 1 exit /b 1
call :verify_hash "!QEMU_ARCHIVE!" "SHA512" "!QEMU_SHA512!" "QEMU"
if errorlevel 1 exit /b 1

call :download "!SEVENZIP_REDUCED_URL!" "!SEVENZIP_REDUCED!" "7-Zip bootstrap"
if errorlevel 1 exit /b 1
call :verify_hash "!SEVENZIP_REDUCED!" "SHA256" "!SEVENZIP_REDUCED_SHA256!" "7-Zip bootstrap"
if errorlevel 1 exit /b 1

call :download "!SEVENZIP_URL!" "!SEVENZIP_ARCHIVE!" "7-Zip"
if errorlevel 1 exit /b 1
call :verify_hash "!SEVENZIP_ARCHIVE!" "SHA256" "!SEVENZIP_SHA256!" "7-Zip"
if errorlevel 1 exit /b 1

"!SEVENZIP_REDUCED!" x "!SEVENZIP_ARCHIVE!" "-o!SEVENZIP_EXTRACT!" -y >nul
if errorlevel 1 (
    echo [ERROR] Could not prepare the portable 7-Zip extractor.
    exit /b 1
)

if not exist "!SEVENZIP_EXTRACT!\7z.exe" (
    echo [ERROR] The 7-Zip package has an unexpected structure.
    exit /b 1
)

"!SEVENZIP_EXTRACT!\7z.exe" x "!QEMU_ARCHIVE!" "-o!QEMU_EXTRACT!" -y >nul
if errorlevel 1 (
    echo [ERROR] Could not extract the QEMU package.
    exit /b 1
)

if exist "!QEMU_EXTRACT!\$PLUGINSDIR" rmdir /S /Q "!QEMU_EXTRACT!\$PLUGINSDIR"
if exist "!QEMU_EXTRACT!\qemu-uninstall.exe" del /F /Q "!QEMU_EXTRACT!\qemu-uninstall.exe"

if not exist "!QEMU_EXTRACT!\qemu-system-x86_64.exe" (
    echo [ERROR] The QEMU package has an unexpected structure.
    exit /b 1
)

call :matches_version "!QEMU_EXTRACT!\qemu-system-x86_64.exe" "--version" "QEMU emulator version !QEMU_VERSION!" "prefix"
if errorlevel 1 (
    echo [ERROR] The extracted QEMU version is not !QEMU_VERSION!.
    exit /b 1
)

rmdir "!QEMU_TARGET!" >nul 2>&1
if exist "!QEMU_TARGET!" (
    echo [ERROR] Could not prepare !QEMU_TARGET! for installation.
    exit /b 1
)
move /Y "!QEMU_EXTRACT!" "!QEMU_TARGET!" >nul
if errorlevel 1 (
    echo [ERROR] Could not install QEMU into !QEMU_TARGET!.
    exit /b 1
)
echo [OK] QEMU installed in !QEMU_TARGET!.
exit /b 0

:matches_version
set "R4OS_SETUP_VERSION_EXE=%~1"
set "R4OS_SETUP_VERSION_ARGUMENT=%~2"
set "R4OS_SETUP_EXPECTED_VERSION=%~3"
set "R4OS_SETUP_VERSION_MODE=%~4"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$lines = @(& $env:R4OS_SETUP_VERSION_EXE $env:R4OS_SETUP_VERSION_ARGUMENT 2>$null); if ($LASTEXITCODE -ne 0 -or $lines.Count -eq 0) { exit 1 }; $line = [string]$lines[0]; if ($env:R4OS_SETUP_VERSION_MODE -eq 'exact') { if ($line -ceq $env:R4OS_SETUP_EXPECTED_VERSION) { exit 0 } } elseif ($line.StartsWith($env:R4OS_SETUP_EXPECTED_VERSION, [System.StringComparison]::Ordinal)) { exit 0 }; exit 1" >nul 2>&1
exit /b !ERRORLEVEL!

:download
echo Downloading %~3...
curl.exe --fail --location --retry 3 --retry-delay 2 --connect-timeout 30 --progress-bar --output "%~2" "%~1"
if errorlevel 1 (
    echo [ERROR] Download failed: %~3.
    exit /b 1
)
exit /b 0

:verify_hash
echo Verifying %~4...
set "R4OS_SETUP_HASH_FILE=%~1"
set "R4OS_SETUP_HASH_ALGORITHM=%~2"
set "ACTUAL_HASH="
for /f "usebackq delims=" %%H in (`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$algorithm = [Security.Cryptography.HashAlgorithm]::Create($env:R4OS_SETUP_HASH_ALGORITHM); if ($null -eq $algorithm) { exit 1 }; $stream = [IO.File]::OpenRead($env:R4OS_SETUP_HASH_FILE); try { $hash = $algorithm.ComputeHash($stream); [BitConverter]::ToString($hash).Replace('-','').ToLowerInvariant() } finally { $stream.Dispose(); $algorithm.Dispose() }"`) do set "ACTUAL_HASH=%%H"
if not defined ACTUAL_HASH (
    echo [ERROR] Could not calculate the checksum for %~4.
    exit /b 1
)
if /I not "!ACTUAL_HASH!"=="%~3" (
    echo [ERROR] Checksum mismatch for %~4.
    exit /b 1
)
exit /b 0

:extract_zip
echo Extracting %~3...
mkdir "%~2" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Could not create the extraction directory for %~3.
    exit /b 1
)
set "R4OS_SETUP_ARCHIVE=%~1"
set "R4OS_SETUP_DESTINATION=%~2"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath $env:R4OS_SETUP_ARCHIVE -DestinationPath $env:R4OS_SETUP_DESTINATION -Force"
if errorlevel 1 (
    echo [ERROR] Could not extract %~3.
    exit /b 1
)
exit /b 0

:cleanup
if not defined TEMP_ROOT exit /b 0
if not exist "!TEMP_ROOT!" exit /b 0
for %%I in ("!TEMP_ROOT!\..") do set "TEMP_PARENT=%%~fI"
if /I not "!TEMP_PARENT!"=="!SETUP_DIR!" (
    echo [ERROR] Refusing to clean a path outside DevKit\Setup.
    exit /b 1
)
rmdir /S /Q "!TEMP_ROOT!"
exit /b 0
