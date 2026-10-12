@echo off
rem RetroBat path helper (Windows) - locate BIOS / ROMS directories.
rem
rem Usage:
rem   retrobat-paths.cmd                    show all key directories
rem   retrobat-paths.cmd roms               show roms dir
rem   retrobat-paths.cmd bios               show bios dir
rem   retrobat-paths.cmd roms <system>      show roms dir of one system
rem   retrobat-paths.cmd check <system>     check roms + bios for one system
rem   retrobat-paths.cmd list               list all system ids
rem
rem Set RETROBAT_ROOT to override root detection.

setlocal enabledelayedexpansion

if defined RETROBAT_ROOT (
  set "ROOT=%RETROBAT_ROOT%"
) else (
  set "ROOT=%~dp0.."
)

pushd "%ROOT%" 2>nul
if errorlevel 1 (
  echo error: cannot enter RetroBat root "%ROOT%" 1>&2
  exit /b 2
)
for %%I in ("%CD%") do set "ROOT=%%~fI"
popd

set "BIOS_DIR=%ROOT%\bios"
set "ROMS_DIR=%ROOT%\roms"
set "SYSTEMS_LST=%ROOT%\system\configgen\systems_names.lst"

set "CMD=%~1"
if "%CMD%"=="" set "CMD=all"

if /i "%CMD%"=="all" goto :all
if /i "%CMD%"=="bios" goto :bios
if /i "%CMD%"=="roms" goto :roms
if /i "%CMD%"=="saves" goto :saves
if /i "%CMD%"=="list" goto :list
if /i "%CMD%"=="check" goto :check
if /i "%CMD%"=="-h" goto :help
if /i "%CMD%"=="--help" goto :help
if /i "%CMD%"=="help" goto :help

echo error: unknown command "%CMD%" ^(try --help^) 1>&2
exit /b 2

:all
echo RetroBat root : %ROOT%
echo BIOS          : %BIOS_DIR%
echo ROMS          : %ROMS_DIR%
echo   saves       : %ROOT%\saves
echo   cheats      : %ROOT%\cheats
echo   emulators   : %ROOT%\emulators
echo   screenshots : %ROOT%\screenshots
echo   system      : %ROOT%\system
echo   user        : %ROOT%\user
echo.
for %%D in ("%BIOS_DIR%" "%ROMS_DIR%") do (
  if exist "%%~fD\" (
    echo [ok]   %%~fD
    powershell -NoProfile -Command "$i = Get-Item -LiteralPath '%%~fD' -Force; if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint -and $i.Target) { '       -> ' + $i.Target }"
  ) else (
    echo [miss] %%~fD
  )
)
exit /b 0

:bios
echo %BIOS_DIR%
exit /b 0

:roms
if "%~2"=="" (echo %ROMS_DIR%) else (echo %ROMS_DIR%\%~2)
exit /b 0

:saves
echo %ROOT%\saves
exit /b 0

:list
if exist "%SYSTEMS_LST%" type "%SYSTEMS_LST%"
echo cgenius
echo quake
echo quake2
echo singe
echo sonicretro
echo sonic-mania
echo switchupdates
echo vpinball
echo halflife
exit /b 0

:check
if "%~2"=="" (
  echo error: missing ^<system^> argument 1>&2
  exit /b 2
)
set "SYS=%~2"
set "RC=0"
if exist "%ROMS_DIR%\%SYS%\" (
  echo [ok]   roms : %ROMS_DIR%\%SYS%
) else (
  echo [miss] roms : %ROMS_DIR%\%SYS%
  set "RC=1"
)
if exist "%BIOS_DIR%\%SYS%\" (
  echo [ok]   bios : %BIOS_DIR%\%SYS%
) else (
  echo [warn] bios : %BIOS_DIR%\%SYS% ^(many systems share bios\ root instead^)
)
exit /b %RC%

:help
echo RetroBat path helper - BIOS / ROMS locator
echo.
echo   retrobat-paths.cmd                    show all key directories
echo   retrobat-paths.cmd roms               show roms dir
echo   retrobat-paths.cmd bios               show bios dir
echo   retrobat-paths.cmd roms ^<system^>      show roms dir of one system
echo   retrobat-paths.cmd check ^<system^>     check roms + bios for one system
echo   retrobat-paths.cmd list               list all system ids
exit /b 0
