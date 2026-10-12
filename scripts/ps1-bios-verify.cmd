@echo off
rem Verify PS1 BIOS dumps placed in a RetroBat install (Windows).
rem
rem RetroBat's DuckStation profile searches ..\..\bios, i.e. RetroBat\bios\ directly.
rem DuckStation identifies a BIOS by content hash only, so the file name does not matter.
rem
rem Usage:
rem   ps1-bios-verify.cmd              scan RetroBat\bios and report
rem   ps1-bios-verify.cmd <dir>        scan a custom directory
rem
rem Hashes come from DuckStation upstream (src/core/bios.cpp, s_image_info_by_hash).
rem This script verifies *your own* dump. It does not download or provide BIOS files.
rem
rem Note: the OpenBIOS signature check is only implemented in ps1-bios-verify.sh.

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "HASHES=%SCRIPT_DIR%ps1-bios-hashes.csv"

if not "%~1"=="" (
  set "TARGET=%~1"
) else (
  if defined RETROBAT_ROOT (
    set "ROOT=%RETROBAT_ROOT%"
  ) else (
    pushd "%SCRIPT_DIR%.." 2>nul
    if errorlevel 1 (
      echo error: cannot resolve RetroBat root from "%SCRIPT_DIR%.." 1>&2
      exit /b 2
    )
    set "ROOT=%CD%"
    popd
  )
  set "TARGET=%ROOT%\bios"
)

if not exist "%HASHES%" (
  echo error: hash table not found: %HASHES% 1>&2
  exit /b 2
)

if not exist "%TARGET%\" (
  echo error: directory not found: %TARGET% 1>&2
  echo hint: set RETROBAT_ROOT or pass the bios directory as the first argument 1>&2
  exit /b 2
)

echo BIOS directory : %TARGET%
echo hash table     : %HASHES%
echo.

set /a TOTAL=0
set /a OK=0
set /a UNK=0
set "FOUND_U="
set "FOUND_J="
set "FOUND_E="

for /r "%TARGET%" %%F in (*.bin *.rom *.img *.bios) do (
  set /a TOTAL+=1
  set "FILE=%%~fF"
  set "NAME=%%~nxF"
  set "FSIZE=%%~zF"
  set "HASH="

  for /f "skip=1 delims=" %%H in ('certutil -hashfile "!FILE!" MD5 2^>nul') do (
    if not defined HASH set "HASH=%%H"
  )
  set "HASH=!HASH: =!"

  set "MATCH="
  set "MATCHREG="
  for /f "usebackq tokens=1-4 delims=," %%A in ("%HASHES%") do (
    if /i "%%A"=="!HASH!" (
      set "MATCH=%%D (v%%B, %%C)"
      set "MATCHREG=%%C"
    )
  )

  if defined MATCH (
    echo [ok]   !NAME!  !MATCH!
    set /a OK+=1
    if /i "!MATCHREG!"=="NTSC-U" set "FOUND_U=1"
    if /i "!MATCHREG!"=="NTSC-J" set "FOUND_J=1"
    if /i "!MATCHREG!"=="PAL" set "FOUND_E=1"
  ) else (
    echo [??]   !NAME!
    echo        md5=!HASH!  size=!FSIZE!
    if not "!FSIZE!"=="524288" echo        note: PS1 BIOS must be exactly 524288 bytes - 512 KiB - size looks wrong
    set /a UNK+=1
  )
)

echo.
if %TOTAL%==0 (
  echo [miss] no candidate BIOS files ^(*.bin/*.rom/*.img/*.bios^) in %TARGET%
  echo.
  echo Place a BIOS dumped from your own console here. DuckStation matches on content,
  echo so any file name works; only the MD5 has to match a known revision.
  exit /b 1
)

echo %OK% recognized, %UNK% unrecognized

if %OK% GTR 0 (
  echo.
  echo Region coverage ^(DuckStation needs a BIOS matching the disc region^):
  if defined FOUND_U (echo   NTSC-U  [ok]) else (echo   NTSC-U  [--])
  if defined FOUND_J (echo   NTSC-J  [ok]) else (echo   NTSC-J  [--])
  if defined FOUND_E (echo   PAL     [ok]) else (echo   PAL     [--])
)

if %UNK% EQU 0 (exit /b 0) else (exit /b 1)
