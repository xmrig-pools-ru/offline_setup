@echo off

set VERSION=2.0

rem printing greetings

echo MoneroOcean mining setup script v%VERSION%.
echo ^(please report issues to support@moneroocean.stream email^)
echo.

net session >nul 2>&1
if %errorLevel% == 0 (set ADMIN=1) else (set ADMIN=0)

rem command line arguments

set WALLET=%1
rem this one is optional
set EMAIL=%2

rem checking prerequisites

if [%WALLET%] == [] (
  for /f "delims=" %%a in ('powershell -Command "(Get-Content -Raw '%~dp0config.json' | ConvertFrom-Json).pools[0].user"') do set WALLET=%%a
)

if [%WALLET%] == [] (
  echo Script usage:
  echo ^> setup_moneroocean_miner.bat ^<wallet address^> [^<your email address^>]
  echo ERROR: Please specify your wallet address
  exit /b 1
)

for /f "delims=." %%a in ("%WALLET%") do set WALLET_BASE=%%a
call :strlen "%WALLET_BASE%", WALLET_BASE_LEN
if %WALLET_BASE_LEN% == 106 goto WALLET_LEN_OK
if %WALLET_BASE_LEN% ==  95 goto WALLET_LEN_OK
echo ERROR: Wrong wallet address length (should be 106 or 95): %WALLET_BASE_LEN%
exit /b 1

:WALLET_LEN_OK

if ["%USERPROFILE%"] == [""] (
  echo ERROR: Please define USERPROFILE environment variable to your user directory
  exit /b 1
)

if not exist "%USERPROFILE%" (
  echo ERROR: Please make sure user directory %USERPROFILE% exists
  exit /b 1
)

where wmic >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "wmic" utility to work correctly
  exit /b 1
)

where powershell >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "powershell" utility to work correctly
  exit /b 1
)

where find >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "find" utility to work correctly
  exit /b 1
)

where findstr >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "findstr" utility to work correctly
  exit /b 1
)

where tasklist >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "tasklist" utility to work correctly
  exit /b 1
)

if %ADMIN% == 1 (
  where sc >NUL
  if not %errorlevel% == 0 (
    echo ERROR: This script requires "sc" utility to work correctly
    exit /b 1
  )
)

rem calculating port

for /f "tokens=*" %%a in ('wmic cpu get SocketDesignation /Format:List ^| findstr /r /v "^$" ^| find /c /v ""') do set CPU_SOCKETS=%%a
if [%CPU_SOCKETS%] == [] ( 
  echo ERROR: Can't get CPU sockets from wmic output
  exit 
)

for /f "tokens=*" %%a in ('wmic cpu get NumberOfCores /Format:List ^| findstr /r /v "^$"') do set CPU_CORES_PER_SOCKET=%%a
for /f "tokens=1,* delims==" %%a in ("%CPU_CORES_PER_SOCKET%") do set CPU_CORES_PER_SOCKET=%%b
if [%CPU_CORES_PER_SOCKET%] == [] ( 
  echo ERROR: Can't get CPU cores per socket from wmic output
  exit 
)

for /f "tokens=*" %%a in ('wmic cpu get NumberOfLogicalProcessors /Format:List ^| findstr /r /v "^$"') do set CPU_THREADS=%%a
for /f "tokens=1,* delims==" %%a in ("%CPU_THREADS%") do set CPU_THREADS=%%b
if [%CPU_THREADS%] == [] ( 
  echo ERROR: Can't get CPU cores from wmic output
  exit 
)
set /a "CPU_THREADS = %CPU_SOCKETS% * %CPU_THREADS%"

for /f "tokens=*" %%a in ('wmic cpu get MaxClockSpeed /Format:List ^| findstr /r /v "^$"') do set CPU_MHZ=%%a
for /f "tokens=1,* delims==" %%a in ("%CPU_MHZ%") do set CPU_MHZ=%%b
if [%CPU_MHZ%] == [] ( 
  echo ERROR: Can't get CPU MHz from wmic output
  exit 
)

for /f "tokens=*" %%a in ('wmic cpu get L2CacheSize /Format:List ^| findstr /r /v "^$"') do set CPU_L2_CACHE=%%a
for /f "tokens=1,* delims==" %%a in ("%CPU_L2_CACHE%") do set CPU_L2_CACHE=%%b
if [%CPU_L2_CACHE%] == [] ( 
  echo ERROR: Can't get L2 CPU cache from wmic output
  exit 
)

for /f "tokens=*" %%a in ('wmic cpu get L3CacheSize /Format:List ^| findstr /r /v "^$"') do set CPU_L3_CACHE=%%a
for /f "tokens=1,* delims==" %%a in ("%CPU_L3_CACHE%") do set CPU_L3_CACHE=%%b
if [%CPU_L3_CACHE%] == [] ( 
  echo ERROR: Can't get L3 CPU cache from wmic output
  exit 
)

set /a "TOTAL_CACHE = %CPU_SOCKETS% * (%CPU_L2_CACHE% / %CPU_CORES_PER_SOCKET% + %CPU_L3_CACHE%)"
if [%TOTAL_CACHE%] == [] ( 
  echo ERROR: Can't compute total cache
  exit 
)

set /a "CACHE_THREADS = %TOTAL_CACHE% / 2048"

if %CPU_THREADS% lss %CACHE_THREADS% (
  set /a "EXP_MONERO_HASHRATE = %CPU_THREADS% * (%CPU_MHZ% * 20 / 1000)"
) else (
  set /a "EXP_MONERO_HASHRATE = %CACHE_THREADS% * (%CPU_MHZ% * 20 / 1000)"
)

if [%EXP_MONERO_HASHRATE%] == [] ( 
  echo ERROR: Can't compute projected Monero hashrate
  exit 
)

if %EXP_MONERO_HASHRATE% gtr 12800 (
  echo ERROR: Wrong ^(too high^) projected Monero hashrate: %EXP_MONERO_HASHRATE%
  exit /b 1
)
if %EXP_MONERO_HASHRATE% gtr 3200  ( set PORT=10128 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 1600  ( set PORT=10064 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 800   ( set PORT=10032 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 400   ( set PORT=10016 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 200   ( set PORT=10008 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr 100   ( set PORT=10004 & goto PORT_OK )
if %EXP_MONERO_HASHRATE% gtr  50   ( set PORT=10002 & goto PORT_OK )
set PORT=10001

:PORT_OK

rem printing intentions

set "LOGFILE=%USERPROFILE%\moneroocean\xmrig.log"

echo I will download, setup and run in background Monero CPU miner with logs in %LOGFILE% file.
echo If needed, miner in foreground can be started by %USERPROFILE%\moneroocean\miner.bat script.
echo Mining will happen to %WALLET% wallet.

if not [%EMAIL%] == [] (
  echo ^(and %EMAIL% email as password to modify wallet options later at https://moneroocean.stream site^)
)

echo.

if %ADMIN% == 0 (
  echo Since I do not have admin access, mining in background will be started using your startup directory script and only work when your are logged in this host.
) else (
  echo Mining in background will be performed using moneroocean_miner service.
)

echo.
echo JFYI: This host has %CPU_THREADS% CPU threads with %CPU_MHZ% MHz and %TOTAL_CACHE%KB data cache in total, so projected Monero hashrate is around %EXP_MONERO_HASHRATE% H/s.
echo.

pause

rem start doing stuff: preparing miner

echo [*] Removing previous moneroocean miner (if any)
sc stop moneroocean_miner
sc delete moneroocean_miner
taskkill /f /t /im xmrig.exe

:REMOVE_DIR0
echo [*] Removing "%USERPROFILE%\moneroocean" directory
timeout 5
rmdir /q /s "%USERPROFILE%\moneroocean" >NUL 2>NUL
IF EXIST "%USERPROFILE%\moneroocean" GOTO REMOVE_DIR0

echo [*] Creating empty "%USERPROFILE%\moneroocean" directory
mkdir "%USERPROFILE%\moneroocean"

echo [*] Copying "%~dp0\xmrig.exe" and "%~dp0\config.json" to "%USERPROFILE%\moneroocean"
copy /Y "%~dp0\xmrig.exe"   "%USERPROFILE%\moneroocean"
copy /Y "%~dp0\config.json" "%USERPROFILE%\moneroocean"

echo [*] Checking if private version of "%USERPROFILE%\moneroocean\xmrig.exe" works fine ^(and not removed by antivirus software^)
echo [*] Leaving "%USERPROFILE%\moneroocean\config.json" unmodified (no replacements)
"%USERPROFILE%\moneroocean\xmrig.exe" --help >NUL
if %ERRORLEVEL% equ 2 goto MINER_OK

if exist "%USERPROFILE%\moneroocean\xmrig.exe" (
  echo WARNING: Private version of "%USERPROFILE%\moneroocean\xmrig.exe" is not functional
) else (
  echo WARNING: Private version of "%USERPROFILE%\moneroocean\xmrig.exe" was removed by antivirus
)

exit /b 1

:MINER_OK

echo [*] Miner "%USERPROFILE%\moneroocean\xmrig.exe" is OK

for /f "tokens=*" %%a in ('powershell -Command "hostname | %%{$_ -replace '[^a-zA-Z0-9]+', '_'}"') do set PASS=%%a
if [%PASS%] == [] (
  set PASS=na
)
if not [%EMAIL%] == [] (
  set "PASS=%PASS%:%EMAIL%"
)

echo [*] Leaving "%USERPROFILE%\moneroocean\config.json" unmodified (no replacements)

set LOGFILE2=%LOGFILE:\=\\%

copy /Y "%USERPROFILE%\moneroocean\config.json" "%USERPROFILE%\moneroocean\config_background.json" >NUL
echo [*] Copied config_background.json without modifications

rem preparing script
(
echo @echo off
echo tasklist /fi "imagename eq xmrig.exe" ^| find ":" ^>NUL
echo if errorlevel 1 goto ALREADY_RUNNING
echo start /low %%~dp0xmrig.exe %%^*
echo goto EXIT
echo :ALREADY_RUNNING
echo echo Monero miner is already running in the background. Refusing to run another one.
echo echo Run "taskkill /IM xmrig.exe" if you want to remove background miner first.
echo :EXIT
) > "%USERPROFILE%\moneroocean\miner.bat"

rem preparing script background work and work under reboot

if %ADMIN% == 1 goto ADMIN_MINER_SETUP

if exist "%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" (
  set "STARTUP_DIR=%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
  goto STARTUP_DIR_OK
)
if exist "%USERPROFILE%\Start Menu\Programs\Startup" (
  set "STARTUP_DIR=%USERPROFILE%\Start Menu\Programs\Startup"
  goto STARTUP_DIR_OK  
)

echo ERROR: Can't find Windows startup directory
exit /b 1

:STARTUP_DIR_OK
echo [*] Adding call to "%USERPROFILE%\moneroocean\miner.bat" script to "%STARTUP_DIR%\moneroocean_miner.bat" script
(
echo @echo off
echo "%USERPROFILE%\moneroocean\miner.bat" --config="%USERPROFILE%\moneroocean\config_background.json"
) > "%STARTUP_DIR%\moneroocean_miner.bat"

echo [*] Running miner in the background
call "%STARTUP_DIR%\moneroocean_miner.bat"
goto OK

:ADMIN_MINER_SETUP


echo [*] Copying "%~dp0\nssm.exe" to "%USERPROFILE%\moneroocean"
copy /Y "%~dp0\nssm.exe" "%USERPROFILE%\moneroocean"

echo [*] Creating moneroocean_miner service
sc stop moneroocean_miner
sc delete moneroocean_miner
"%USERPROFILE%\moneroocean\nssm.exe" install moneroocean_miner "%USERPROFILE%\moneroocean\xmrig.exe"
if errorlevel 1 (
  echo ERROR: Can't create moneroocean_miner service
  exit /b 1
)
"%USERPROFILE%\moneroocean\nssm.exe" set moneroocean_miner AppDirectory "%USERPROFILE%\moneroocean"
"%USERPROFILE%\moneroocean\nssm.exe" set moneroocean_miner AppPriority BELOW_NORMAL_PRIORITY_CLASS
"%USERPROFILE%\moneroocean\nssm.exe" set moneroocean_miner AppStdout "%USERPROFILE%\moneroocean\stdout"
"%USERPROFILE%\moneroocean\nssm.exe" set moneroocean_miner AppStderr "%USERPROFILE%\moneroocean\stderr"

echo [*] Starting moneroocean_miner service
"%USERPROFILE%\moneroocean\nssm.exe" start moneroocean_miner
if errorlevel 1 (
  echo ERROR: Can't start moneroocean_miner service
  exit /b 1
)

echo
echo Please reboot system if moneroocean_miner service is not activated yet (if "%USERPROFILE%\moneroocean\xmrig.log" file is empty)
goto OK

:OK
echo
echo [*] Setup complete
pause
exit /b 0

:strlen string len
setlocal EnableDelayedExpansion
set "token=#%~1" & set "len=0"
for /L %%A in (12,-1,0) do (
  set/A "len|=1<<%%A"
  for %%B in (!len!) do if "!token:~%%B,1!"=="" set/A "len&=~1<<%%A"
)
endlocal & set %~2=%len%
exit /b
