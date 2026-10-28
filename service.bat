@echo off
set "LOCAL_VERSION=1.10.4"

:: External commands
if "%~1"=="status_zapret" (
    call :test_service zapret soft
    call :tcp_enable
    exit /b
)

if "%~1"=="check_updates" (
    if defined NO_UPDATE_CHECK exit /b

    if exist "%~dp0utils\check_updates.enabled" (
        if not "%~2"=="soft" (
            start /b service check_updates soft
        ) else (
            call :service_check_updates soft
        )
    )

    exit /b
)

if "%~1"=="load_game_filter" (
    call :game_switch_status
    exit /b
)

if "%~1"=="load_fix_settings" goto external_load_fix_settings
if /i "%~1"=="install_strategy_auto" goto external_install_strategy_auto

if "%~1"=="load_user_lists" (
    call :load_user_lists
    exit /b
)

set "UI_LANG=en"
for /f "delims=" %%L in ('powershell -NoProfile -Command "$c = [System.Globalization.CultureInfo]::CurrentUICulture.Name; try { $override = Get-WinUILanguageOverride; if ($override) { $c = [string]$override } } catch {}; if ($c -match '^(?i:ru)(-|$)') { 'ru' } else { 'en' }" 2^>nul') do set "UI_LANG=%%L"
call :set_ui_codepage

if "%1"=="admin" (
    call :check_command chcp
    call :check_command find
    call :check_command findstr
    call :check_command netsh
    
    call :load_user_lists

    call :ui_echo "Started with admin rights" "Запуск с правами администратора"
) else (
    call :check_extracted
    call :check_command powershell

    call :ui_echo "Requesting admin rights..." "Запрашиваются права администратора..."
    powershell -NoProfile -Command "Start-Process 'cmd.exe' -ArgumentList '/c \"\"%~f0\" admin\"' -Verb RunAs"
    exit
)


:: MENU ================================
setlocal EnableDelayedExpansion
if /i "!UI_LANG!"=="ru" (title МЕНЕДЖЕР ZAPRET v!LOCAL_VERSION!) else title ZAPRET SERVICE MANAGER v!LOCAL_VERSION!
:menu

cls

call :ipset_switch_status
call :game_switch_status
call :check_updates_switch_status
call :fix_filters_status
call :update_status_labels
call :get_strategy_name

set "menu_choice=null"

echo.
call :ui_echo "ZAPRET SERVICE MANAGER v!LOCAL_VERSION!" "МЕНЕДЖЕР ZAPRET v!LOCAL_VERSION!"
echo.  !CurrentStrategy!
call :ui_echo "   ----------------------------------------" "   ----------------------------------------"
echo.
call :ui_echo "   :: SERVICE" "   :: СЛУЖБА"
call :ui_echo "      1. Install Service" "      1. Установить службу"
call :ui_echo "      2. Remove Services" "      2. Удалить службы"
call :ui_echo "      3. Check Status" "      3. Проверить состояние"
echo.
call :ui_echo "   :: SETTINGS" "   :: НАСТРОЙКИ"
call :ui_echo "      4. Game Filter         [!GameFilterStatus!]" "      4. Фильтр игр          [!GameFilterStatusDisplay!]"
call :ui_echo "      5. IPSet Filter        [!IPsetStatus!]" "      5. Фильтр IPSet        [!IPsetStatusDisplay!]"
call :ui_echo "      6. Auto-Update Check   [!CheckUpdatesStatus!]" "      6. Автопроверка обновлений [!CheckUpdatesStatusDisplay!]"
call :ui_echo "      7. Replace active fakes" "      7. Заменить активные фейки"
echo.
call :ui_echo "   :: UPDATES" "   :: ОБНОВЛЕНИЯ"
call :ui_echo "      8. Update IPSet List" "      8. Обновить список IPSet"
call :ui_echo "      9. Update Hosts File" "      9. Обновить файл Hosts"
call :ui_echo "      10. Check for Updates" "      10. Проверить обновления"
echo.
call :ui_echo "   :: TOOLS" "   :: ИНСТРУМЕНТЫ"
call :ui_echo "      11. Run Diagnostics" "      11. Диагностика"
call :ui_echo "      12. Run Tests" "      12. Тесты"
call :ui_echo "      13. Custom Fixes (WARP/Minecraft/Auto) [WARP: !WarpFilterStatus!, Minecraft: !MinecraftFilterStatus!, Auto pick: !AutoStrategyStatus!, AutoHostlist: !AutoHostlistStatus!]" "      13. Доп. фиксы (WARP/Minecraft/авто) [WARP: !WarpFilterStatus!, Minecraft: !MinecraftFilterStatus!, Автовыбор: !AutoStrategyStatus!, AutoHostlist: !AutoHostlistStatus!]"
echo.
call :ui_echo "   ----------------------------------------" "   ----------------------------------------"
call :ui_echo "      0. Exit" "      0. Выход"
echo.

call :ui_prompt menu_choice "   Select option (0-13): " "   Выберите пункт (0–13): "

if "%menu_choice%"=="1" goto service_install
if "%menu_choice%"=="2" goto service_remove
if "%menu_choice%"=="3" goto service_status
if "%menu_choice%"=="4" goto game_switch
if "%menu_choice%"=="5" goto ipset_switch
if "%menu_choice%"=="6" goto check_updates_switch
if "%menu_choice%"=="7" goto replace_active_fakes
if "%menu_choice%"=="8" goto ipset_update
if "%menu_choice%"=="9" goto hosts_update
if "%menu_choice%"=="10" goto service_check_updates
if "%menu_choice%"=="11" goto service_diagnostics
if "%menu_choice%"=="12" goto run_tests
if "%menu_choice%"=="13" goto fix_filters_menu
if "%menu_choice%"=="0" exit /b
goto menu


:: LOAD USER LISTS =====================
:load_user_lists
set "LISTS_PATH=%~dp0lists\"

if not exist "%LISTS_PATH%ipset-exclude-user.txt" (
    echo 203.0.113.113/32>"%LISTS_PATH%ipset-exclude-user.txt"
)
if not exist "%LISTS_PATH%list-general-user.txt" (
    echo # Never leave this file empty>"%LISTS_PATH%list-general-user.txt"
    echo domain.example.abc>>"%LISTS_PATH%list-general-user.txt"
)
if not exist "%LISTS_PATH%list-exclude-user.txt" (
    echo domain.example.abc>"%LISTS_PATH%list-exclude-user.txt"
)

exit /b


:: TCP ENABLE ==========================
:tcp_enable
call :set_ui_codepage
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" > nul || netsh interface tcp set global timestamps=enabled > nul 2>&1
exit /b


:: STATUS ==============================
:service_status
cls
call :set_ui_codepage
sc query "zapret" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube 2^>nul') do echo Service strategy installed from "%%B"
)

call :test_service zapret
call :test_service WinDivert

set "BIN_PATH=%~dp0bin\"
if not exist "%BIN_PATH%\*.sys" (
    call :ui_print PrintRed "WinDivert64.sys file NOT found." "Файл WinDivert64.sys НЕ найден."
)
echo:

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if !errorlevel!==0 (
    call :ui_print PrintGreen "Bypass (winws.exe) is RUNNING." "Обход (winws.exe) ЗАПУЩЕН."
) else (
    call :ui_print PrintRed "Bypass (winws.exe) is NOT running." "Обход (winws.exe) НЕ запущен."
)

pause
goto menu

:test_service
set "ServiceName=%~1"
set "ServiceStatus="

for /f "tokens=3 delims=: " %%A in ('sc query "%ServiceName%" ^| findstr /i "STATE"') do set "ServiceStatus=%%A"
set "ServiceStatus=%ServiceStatus: =%"

if "%ServiceStatus%"=="RUNNING" (
    if "%~2"=="soft" (
        call :ui_echo "%ServiceName% is ALREADY RUNNING as a service. Use Remove Services before launching a strategy separately." "Служба %ServiceName% уже запущена. Перед отдельным запуском стратегии сначала выберите «Удалить службы»."
        pause
        exit /b
    ) else (
        call :ui_echo "Service %ServiceName% is RUNNING." "Служба %ServiceName% запущена."
    )
) else if "%ServiceStatus%"=="STOP_PENDING" (
    call :ui_print PrintYellow "%ServiceName% is STOP_PENDING, that may be caused by a conflict with another bypass. Run Diagnostics to try to fix conflicts" "Служба %ServiceName% находится в состоянии STOP_PENDING; возможен конфликт с другой программой обхода. Запустите диагностику."
) else if not "%~2"=="soft" (
    call :ui_echo "Service %ServiceName% is NOT running." "Служба %ServiceName% не запущена."
)

exit /b


:: REMOVE ==============================
:service_remove
cls
chcp 65001 > nul

set SRVCNAME=zapret
sc query "!SRVCNAME!" >nul 2>&1
if !errorlevel!==0 (
    net stop %SRVCNAME%
    sc delete %SRVCNAME%
) else (
    call :ui_echo "Service %SRVCNAME% is not installed." "Служба %SRVCNAME% не установлена."
)

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if !errorlevel!==0 (
    taskkill /IM winws.exe /F > nul
)

sc query "WinDivert" >nul 2>&1
if !errorlevel!==0 (
    net stop "WinDivert"

    sc query "WinDivert" >nul 2>&1
    if !errorlevel!==0 (
        sc delete "WinDivert"
    )
)
net stop "WinDivert14" >nul 2>&1
sc delete "WinDivert14" >nul 2>&1

pause
goto menu


:: INSTALL =============================
:service_install
cls
call :set_ui_codepage
:: Main
cd /d "%~dp0"
set "BIN_PATH=%~dp0bin\"
set "LISTS_PATH=%~dp0lists\"

:: Searching for .bat files in current folder, except files that start with "service"
call :ui_echo "Pick one of the options:" "Выберите один из вариантов:"
set "count=0"
for /f "delims=" %%F in ('powershell -NoProfile -Command "Get-ChildItem -LiteralPath '.' -Filter '*.bat' | Where-Object { $_.Name -notlike 'service*' } | Sort-Object { [Regex]::Replace($_.Name, '(\d+)', { $args[0].Value.PadLeft(8, '0') }) } | ForEach-Object { $_.Name }"') do (
    set /a count+=1
    echo   !count!. %%F
    set "file!count!=%%F"
)

call :ui_echo "   0. Exit" "   0. Выход"

echo.

:: Choosing file
set "choice="
call :ui_prompt choice "Input option (0-!count!, default: 0): " "Введите номер (0–!count!, по умолчанию 0): "
if "!choice!"=="" (
    set "choice=0"
)

if "!choice!"=="0" (
    goto menu
)

set "selectedFile=!file%choice%!"
if not defined selectedFile (
    call :ui_echo "Invalid choice, exiting..." "Неверный выбор, выход..."
    pause
    goto menu
)
goto service_install_prepare

:service_install_existing
cls
call :set_ui_codepage
cd /d "%~dp0"
set "BIN_PATH=%~dp0bin\"
set "LISTS_PATH=%~dp0lists\"
set "existingStrategy="
for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube 2^>nul') do set "existingStrategy=%%B"
if not defined existingStrategy (
    call :ui_print PrintRed "No previously installed strategy was found. Use Install Service first." "Ранее установленная стратегия не найдена. Сначала используйте «Установить службу»."
    pause
    goto menu
)
set "selectedFile=%~dp0!existingStrategy!.bat"
if not exist "!selectedFile!" (
    call :ui_print PrintRed "Previously installed strategy file was not found: !selectedFile!" "Файл ранее установленной стратегии не найден: !selectedFile!"
    pause
    goto menu
)
goto service_install_prepare

:service_install_prepare
call :load_fix_settings
call :refresh_minecraft_domains
set "ZAPRET_STRATEGY_SOURCE=!selectedFile!"
set "ZAPRET_STRATEGY_TEMP=%TEMP%\zapret_strategy_!RANDOM!_!RANDOM!.bat"
set "ZAPRET_MINECRAFT_FILTER_WF=!MinecraftFilterWF!"
set "ZAPRET_WARP_FILTER_WF=!WarpFilterWF!"
set "ZAPRET_MINECRAFT_FILTER_SKIP=!MinecraftFilterSkip!"
set "ZAPRET_WARP_FILTER_SKIP=!WarpFilterSkip!"
set "ZAPRET_AUTOHOSTLIST_SKIP=!AutoHostlistSkip!"
powershell -NoProfile -Command ^
    "$strategyText = [System.IO.File]::ReadAllText($env:ZAPRET_STRATEGY_SOURCE);" ^
    "$strategyText = $strategyText.Replace(([string][char]37 + 'MinecraftFilterWF' + [string][char]37), [string]$env:ZAPRET_MINECRAFT_FILTER_WF);" ^
    "$strategyText = $strategyText.Replace(([string][char]37 + 'WarpFilterWF' + [string][char]37), [string]$env:ZAPRET_WARP_FILTER_WF);" ^
    "$strategyText = $strategyText.Replace(([string][char]37 + 'MinecraftFilterSkip' + [string][char]37), [string]$env:ZAPRET_MINECRAFT_FILTER_SKIP);" ^
    "$strategyText = $strategyText.Replace(([string][char]37 + 'WarpFilterSkip' + [string][char]37), [string]$env:ZAPRET_WARP_FILTER_SKIP);" ^
    "$strategyText = $strategyText.Replace(([string][char]37 + 'AutoHostlistSkip' + [string][char]37), [string]$env:ZAPRET_AUTOHOSTLIST_SKIP);" ^
    "[System.IO.File]::WriteAllText($env:ZAPRET_STRATEGY_TEMP, $strategyText, [System.Text.UTF8Encoding]::new($false))"
if not exist "!ZAPRET_STRATEGY_TEMP!" (
    call :ui_print PrintRed "Failed to prepare strategy using the current fix settings." "Не удалось подготовить стратегию с текущими настройками фиксов."
    pause
    goto menu
)

:: Args that should be followed by value
set "args_with_value=sni host altorder"

:: Parsing args (mergeargs: 2=start param|3=arg with value|1=params args|0=default)
set "args="
set "capture=0"
set "mergeargs=0"
set "BIN=%~dp0bin\"
set "LISTS=%~dp0lists\"
set QUOTE="

for /f "tokens=*" %%a in ('type "!ZAPRET_STRATEGY_TEMP!"') do (
    set "line=%%a"
    call set "line=%%line:^!=EXCL_MARK%%"
    call set "line=!line!"

    echo !line! | findstr /i "winws.exe" >nul
    if not errorlevel 1 (
        set "capture=1"
    )

    if !capture!==1 (
        if not defined args (
            set "line=!line:*winws.exe"=!"
        )

        set "temp_args="
        for %%i in (!line!) do (
            set "arg=%%i"

            if not "!arg!"=="^" if not "!arg!"=="^^" (
                if "!arg:~0,2!" EQU "--" if not !mergeargs!==0 (
                    set "mergeargs=0"
                )

                if "!arg:~0,1!" EQU "!QUOTE!" (
                    set "arg=!arg:~1,-1!"

                    echo !arg! | findstr ":" >nul
                    if !errorlevel!==0 (
                        set "arg=\!QUOTE!!arg!\!QUOTE!"
                    ) else if "!arg:~0,1!"=="@" (
                        set "arg=\!QUOTE!@%~dp0!arg:~1!\!QUOTE!"
                    ) else (
                        set "arg=\!QUOTE!%~dp0!arg!\!QUOTE!"
                    )
                )

                if !mergeargs!==1 (
                    set "temp_args=!temp_args!,!arg!"
                ) else if !mergeargs!==3 (
                    set "temp_args=!temp_args!=!arg!"
                    set "mergeargs=1"
                ) else (
                    set "temp_args=!temp_args! !arg!"
                )

                if "!arg:~0,2!" EQU "--" (
                    set "mergeargs=2"
                ) else if !mergeargs! GEQ 1 (
                    if !mergeargs!==2 set "mergeargs=1"

                    for %%x in (!args_with_value!) do (
                        if /i "%%x"=="!arg!" (
                            set "mergeargs=3"
                        )
                    )
                )
            )
        )

        if not "!temp_args!"=="" (
            set "args=!args! !temp_args!"
        )
    )
)

:: Creating service with parsed args
call :tcp_enable

set ARGS=%args%
call set "ARGS=%%ARGS:EXCL_MARK=^!%%"
call :ui_echo "Final args: !ARGS!" "Итоговые аргументы: !ARGS!"
set SRVCNAME=zapret

net stop %SRVCNAME% >nul 2>&1
sc delete %SRVCNAME% >nul 2>&1
sc create %SRVCNAME% binPath= "\"%BIN_PATH%winws.exe\" !ARGS!" DisplayName= "zapret" start= auto
sc description %SRVCNAME% "Zapret DPI bypass software"
sc start %SRVCNAME%
for %%F in ("!selectedFile!") do set "filename=%%~nF"
reg add "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube /t REG_SZ /d "!filename!" /f
if exist "!ZAPRET_STRATEGY_TEMP!" del /f /q "!ZAPRET_STRATEGY_TEMP!" >nul 2>&1

if defined AUTO_INSTALL_NONINTERACTIVE (
    for /l %%N in (1,1,15) do (
        sc query "zapret" | findstr /I "RUNNING" >nul
        if not errorlevel 1 exit /b 0
        timeout /t 1 /nobreak >nul
    )
    exit /b 1
)

pause
goto menu


:: CHECK UPDATES =======================
:service_check_updates
call :set_ui_codepage
cls

:: Set current version and URLs
set "GITHUB_VERSION_URL=https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/version.txt"
set "GITHUB_RELEASE_URL=https://github.com/Flowseal/zapret-discord-youtube/releases/tag/"
set "GITHUB_DOWNLOAD_URL=https://github.com/Flowseal/zapret-discord-youtube/releases/latest"

:: Get the latest version from GitHub
for /f "delims=" %%A in ('powershell -NoProfile -Command "(Invoke-WebRequest -Uri \"%GITHUB_VERSION_URL%\" -Headers @{\"Cache-Control\"=\"no-cache\"} -UseBasicParsing -TimeoutSec 5).Content.Trim()" 2^>nul') do set "GITHUB_VERSION=%%A"

:: Error handling
if not defined GITHUB_VERSION (
    call :ui_echo "Warning: failed to fetch the latest version. This warning does not affect the operation of zapret" "Предупреждение: не удалось получить последнюю версию. Это не влияет на работу zapret"
    timeout /T 9
    if "%1"=="soft" exit 
    goto menu
)

:: Version comparison
if "%LOCAL_VERSION%"=="%GITHUB_VERSION%" (
    call :ui_echo "Latest version installed: %LOCAL_VERSION%" "Установлена последняя версия: %LOCAL_VERSION%"
    
    if "%1"=="soft" exit 
    pause
    goto menu
) 

call :ui_echo "New version available: %GITHUB_VERSION%" "Доступна новая версия: %GITHUB_VERSION%"
call :ui_echo "Release page: %GITHUB_RELEASE_URL%%GITHUB_VERSION%" "Страница релиза: %GITHUB_RELEASE_URL%%GITHUB_VERSION%"

call :ui_echo "Opening the download page..." "Открывается страница загрузки..."
start "" "%GITHUB_DOWNLOAD_URL%"


if "%1"=="soft" exit 
pause
goto menu



:: DIAGNOSTICS =========================
:service_diagnostics
call :set_ui_codepage
cls

:: Zapret path
call :ui_print PrintGreen "Zapret is installed in: '%~dp0'" "Zapret установлен в: '%~dp0'"
echo:

:: Base Filtering Engine
sc query BFE | findstr /I "RUNNING" > nul
if !errorlevel!==0 (
    call :ui_print PrintGreen "Base Filtering Engine check passed" "Проверка Base Filtering Engine пройдена"
) else (
    call :ui_print PrintRed "[X] Base Filtering Engine is not running. This service is required for zapret to work" "[X] Base Filtering Engine не запущена. Эта служба необходима для работы zapret"
)
echo:

:: Proxy check
set "proxyEnabled=0"
set "proxyServer="

for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul ^| findstr /i "ProxyEnable"') do (
    if "%%B"=="0x1" set "proxyEnabled=1"
)

if !proxyEnabled!==1 (
    for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul ^| findstr /i "ProxyServer"') do (
        set "proxyServer=%%B"
    )
    
    call :ui_print PrintYellow "[?] System proxy is enabled: !proxyServer!" "[?] В системе включён прокси: !proxyServer!"
    call :ui_print PrintYellow "Make sure it's valid or disable it if you don't use a proxy" "Проверьте настройки прокси или отключите его, если не используете"
) else (
    call :ui_print PrintGreen "Proxy check passed" "Проверка прокси пройдена"
)
echo:

:: TCP timestamps check
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" > nul
if !errorlevel!==0 (
    call :ui_print PrintGreen "TCP timestamps check passed" "Проверка TCP timestamps пройдена"
) else (
    call :ui_print PrintYellow "[?] TCP timestamps are disabled. Enabling timestamps..." "[?] TCP timestamps отключены. Включение..."
    netsh interface tcp set global timestamps=enabled > nul 2>&1
    if !errorlevel!==0 (
        call :ui_print PrintGreen "TCP timestamps successfully enabled" "TCP timestamps успешно включены"
    ) else (
        call :ui_print PrintRed "[X] Failed to enable TCP timestamps" "[X] Не удалось включить TCP timestamps"
    )
)
echo:

:: AdguardSvc.exe
tasklist /FI "IMAGENAME eq AdguardSvc.exe" | find /I "AdguardSvc.exe" > nul
if !errorlevel!==0 (
    call :ui_print PrintRed "[X] Adguard process found. Adguard may cause problems with Discord" "[X] Обнаружен процесс Adguard. Он может вызывать проблемы с Discord"
    call :PrintRed "https://github.com/Flowseal/zapret-discord-youtube/issues/417"
) else (
    call :ui_print PrintGreen "Adguard check passed" "Проверка Adguard пройдена"
)
echo:

:: Killer
sc query | findstr /I "Killer" > nul
if !errorlevel!==0 (
    call :ui_print PrintRed "[X] Killer services found. Killer conflicts with zapret" "[X] Обнаружены службы Killer, конфликтующие с zapret"
    call :PrintRed "https://github.com/Flowseal/zapret-discord-youtube/issues/2512#issuecomment-2821119513"
) else (
    call :ui_print PrintGreen "Killer check passed" "Проверка Killer пройдена"
)
echo:

:: Intel Connectivity Network Service
sc query | findstr /I "Intel" | findstr /I "Connectivity" | findstr /I "Network" > nul
if !errorlevel!==0 (
    call :ui_print PrintRed "[X] Intel Connectivity Network Service found. It conflicts with zapret" "[X] Обнаружена служба Intel Connectivity Network Service, конфликтующая с zapret"
    call :PrintRed "https://github.com/ValdikSS/GoodbyeDPI/issues/541#issuecomment-2661670982"
) else (
    call :ui_print PrintGreen "Intel Connectivity check passed" "Проверка Intel Connectivity пройдена"
)
echo:

:: Check Point
set "checkpointFound=0"
sc query | findstr /I "TracSrvWrapper" > nul
if !errorlevel!==0 (
    set "checkpointFound=1"
)

sc query | findstr /I "EPWD" > nul
if !errorlevel!==0 (
    set "checkpointFound=1"
)

if !checkpointFound!==1 (
    call :ui_print PrintRed "[X] Check Point services found. Check Point conflicts with zapret" "[X] Обнаружены службы Check Point, конфликтующие с zapret"
    call :ui_print PrintRed "Try to uninstall Check Point" "Попробуйте удалить Check Point"
) else (
    call :ui_print PrintGreen "Check Point check passed" "Проверка Check Point пройдена"
)
echo:

:: SmartByte
sc query | findstr /I "SmartByte" > nul
if !errorlevel!==0 (
    call :ui_print PrintRed "[X] SmartByte services found. SmartByte conflicts with zapret" "[X] Обнаружены службы SmartByte, конфликтующие с zapret"
    call :ui_print PrintRed "Try to uninstall or disable SmartByte through services.msc" "Попробуйте удалить или отключить SmartByte через services.msc"
) else (
    call :ui_print PrintGreen "SmartByte check passed" "Проверка SmartByte пройдена"
)
echo:

:: Cyrillic path
powershell -NoProfile -Command "if ('%~dp0' -match '[\u0430-\u044F\u0410-\u042F\u0451\u0401]') { exit 0 } else { exit 1 }"
if !errorlevel!==0 (
    call :ui_print PrintYellow "[?] The path where Zapret is installed contains Cyrillic characters" "[?] Путь к папке Zapret содержит кириллические символы"
    call :ui_print PrintYellow "If bypass doesn't work, try to move Zapret to another directory, for example in C:\zapret" "Если обход не работает, перенесите Zapret в другой каталог, например C:\zapret"
) else (
    call :ui_print PrintGreen "Cyrillic path check passed" "Проверка кириллических символов в пути пройдена"
)
echo:

:: OneDrive
if defined OneDrive (
    echo %~dp0\ | findstr /I /C:"%OneDrive%\\" > nul
    if !errorlevel!==0 (
        call :ui_print PrintRed "[X] Zapret is installed in a OneDrive folder" "[X] Zapret установлен в папке OneDrive"
        call :ui_print PrintRed "If bypass doesn't work, try to move Zapret to another directory, for example in C:\zapret" "Если обход не работает, перенесите Zapret в другой каталог, например C:\zapret"
    ) else (
        call :ui_print PrintGreen "OneDrive check passed" "Проверка OneDrive пройдена"
    )
) else (
    call :ui_print PrintGreen "OneDrive check passed" "Проверка OneDrive пройдена"
)
echo:

:: WinDivert64.sys file
set "BIN_PATH=%~dp0bin\"
if not exist "%BIN_PATH%\*.sys" (
    call :ui_print PrintRed "WinDivert64.sys file NOT found." "Файл WinDivert64.sys НЕ найден."
    echo:
)

:: VPN
set "VPN_SERVICES="
sc query | findstr /I "VPN HappService" > nul
if !errorlevel!==0 (
    for /f "tokens=2 delims=:" %%A in ('sc query ^| findstr /I "VPN HappService"') do (
        if not defined VPN_SERVICES (
            set "VPN_SERVICES=!VPN_SERVICES!%%A"
        ) else (
            set "VPN_SERVICES=!VPN_SERVICES!,%%A"
        )
    )
    call :ui_print PrintYellow "[?] VPN services found:!VPN_SERVICES!. Some VPNs can conflict with zapret" "[?] Найдены VPN-службы: !VPN_SERVICES!. Некоторые VPN могут конфликтовать с zapret"
    call :ui_print PrintYellow "Make sure that all VPNs are disabled" "Убедитесь, что все VPN отключены"
) else (
    call :ui_print PrintGreen "VPN check passed" "Проверка VPN пройдена"
)
echo:

:: DNS
set "dohfound=0"
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-ChildItem -Recurse -Path 'HKLM:System\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\' | Get-ItemProperty | Where-Object { $_.DohFlags -gt 0 } | Measure-Object | Select-Object -ExpandProperty Count"') do (
    if %%a gtr 0 (
        set "dohfound=1"
    )
)
if !dohfound!==0 (
    call :ui_print PrintYellow "[?] Make sure you have configured secure DNS in a browser with some non-default DNS service provider," "[?] Настройте защищённый DNS в браузере, выбрав стороннего DNS-провайдера,"
    call :ui_print PrintYellow "If you use Windows 11 you can configure encrypted DNS in the Settings to hide this warning" "В Windows 11 можно настроить шифрованный DNS в параметрах, чтобы убрать это предупреждение"
) else (
    call :ui_print PrintGreen "Secure DNS check passed" "Проверка защищённого DNS пройдена"
)
echo:

:: Hosts file check
set "hostsFile=%SystemRoot%\System32\drivers\etc\hosts"
if exist "%hostsFile%" (
    set "yt_found=0"
    >nul 2>&1 findstr /I "youtube.com" "%hostsFile%" && set "yt_found=1"
    >nul 2>&1 findstr /I "youtu.be" "%hostsFile%" && set "yt_found=1"
    if !yt_found!==1 (
        call :ui_print PrintYellow "[?] Your hosts file contains entries for youtube.com or youtu.be. This may cause problems with YouTube access" "[?] В файле Hosts есть записи youtube.com или youtu.be. Это может мешать открытию YouTube"
    )
)

:: WinDivert conflict
tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
set "winws_running=!errorlevel!"

sc query "WinDivert" | findstr /I "RUNNING STOP_PENDING" > nul
set "windivert_running=!errorlevel!"

if !winws_running! neq 0 if !windivert_running!==0 (
    call :ui_print PrintYellow "[?] winws.exe is not running but WinDivert service is active. Attempting to delete WinDivert..." "[?] winws.exe не запущен, но служба WinDivert активна. Попытка удалить WinDivert..."
    
    net stop "WinDivert" >nul 2>&1
    sc delete "WinDivert" >nul 2>&1
    sc query "WinDivert" >nul 2>&1
    if !errorlevel!==0 (
        call :ui_print PrintRed "[X] Failed to delete WinDivert. Checking for conflicting services..." "[X] Не удалось удалить WinDivert. Проверка конфликтующих служб..."
        
        set "conflicting_services=GoodbyeDPI"
        set "found_conflict=0"
        
        for %%s in (!conflicting_services!) do (
            set "conflictingService=%%s"
            sc query "!conflictingService!" >nul 2>&1
            if !errorlevel!==0 (
                call :ui_print PrintYellow "[?] Found conflicting service: !conflictingService!. Stopping and removing..." "[?] Найдена конфликтующая служба: !conflictingService!. Остановка и удаление..."
                net stop "!conflictingService!" >nul 2>&1
                sc delete "!conflictingService!" >nul 2>&1
                if !errorlevel!==0 (
                    call :ui_print PrintGreen "Successfully removed service: !conflictingService!" "Служба !conflictingService! успешно удалена"
                ) else (
                    call :ui_print PrintRed "[X] Failed to remove service: !conflictingService!" "[X] Не удалось удалить службу !conflictingService!"
                )
                set "found_conflict=1"
            )
        )
        
        if !found_conflict!==0 (
            call :ui_print PrintRed "[X] No conflicting services found. Check manually if any other bypass is using WinDivert." "[X] Конфликтующие службы не найдены. Проверьте, не использует ли WinDivert другая программа обхода."
        ) else (
            call :ui_print PrintYellow "[?] Attempting to delete WinDivert again..." "[?] Повторная попытка удалить WinDivert..."

            net stop "WinDivert" >nul 2>&1
            sc delete "WinDivert" >nul 2>&1
            sc query "WinDivert" >nul 2>&1
            if !errorlevel! neq 0 (
                call :ui_print PrintGreen "WinDivert successfully deleted after removing conflicting services" "WinDivert успешно удалён после удаления конфликтующих служб"
            ) else (
                call :ui_print PrintRed "[X] WinDivert still cannot be deleted. Check manually if any other bypass is using WinDivert." "[X] WinDivert всё ещё не удаётся удалить. Проверьте, не использует ли WinDivert другая программа обхода."
            )
        )
    ) else (
        call :ui_print PrintGreen "WinDivert successfully removed" "WinDivert успешно удалён"
    )
    
    echo:
)

:: Conflicting bypasses
set "conflicting_services=GoodbyeDPI discordfix_zapret winws1 winws2"
set "found_any_conflict=0"
set "found_conflicts="

for %%s in (!conflicting_services!) do (
    sc query "%%s" >nul 2>&1
    if !errorlevel!==0 (
        if "!found_conflicts!"=="" (
            set "found_conflicts=%%s"
        ) else (
            set "found_conflicts=!found_conflicts! %%s"
        )
        set "found_any_conflict=1"
    )
)

if !found_any_conflict!==1 (
    call :ui_print PrintRed "[X] Conflicting bypass services found: !found_conflicts!" "[X] Обнаружены конфликтующие службы обхода: !found_conflicts!"
    
    set "CHOICE="
    call :ui_prompt CHOICE "Do you want to remove these conflicting services? (Y/N) (default: N) " "Удалить эти конфликтующие службы? (Y/N, по умолчанию N) "
    if "!CHOICE!"=="" set "CHOICE=N"
    if "!CHOICE!"=="y" set "CHOICE=Y"
    
    if /i "!CHOICE!"=="Y" (
        for %%s in (!found_conflicts!) do (
            call :ui_print PrintYellow "Stopping and removing service: %%s" "Остановка и удаление службы: %%s"
            net stop "%%s" >nul 2>&1
            sc delete "%%s" >nul 2>&1
            if !errorlevel!==0 (
                call :ui_print PrintGreen "Successfully removed service: %%s" "Служба успешно удалена: %%s"
            ) else (
                call :ui_print PrintRed "[X] Failed to remove service: %%s" "[X] Не удалось удалить службу: %%s"
            )
        )

        net stop "WinDivert" >nul 2>&1
        sc delete "WinDivert" >nul 2>&1
        net stop "WinDivert14" >nul 2>&1
        sc delete "WinDivert14" >nul 2>&1
    )
    
    echo:
)

:: Discord cache clearing
set "CHOICE="
call :ui_prompt CHOICE "Do you want to clear the Discord cache (Stable, PTB, Canary, Development)? (Y/N) (default: Y) " "Очистить кэш Discord (Stable, PTB, Canary, Development)? (Y/N, по умолчанию Y) "
if "!CHOICE!"=="" set "CHOICE=Y"
if "!CHOICE!"=="y" set "CHOICE=Y"

if /i "!CHOICE!"=="Y" (
    set "discordFound=0"
    if exist "%APPDATA%\discord\" (
        set "discordFound=1"
        call :clear_discord_cache "Discord.exe" "Discord" "%APPDATA%\discord"
    )
    if exist "%APPDATA%\discordptb\" (
        set "discordFound=1"
        call :clear_discord_cache "DiscordPTB.exe" "Discord PTB" "%APPDATA%\discordptb"
    )
    if exist "%APPDATA%\discordcanary\" (
        set "discordFound=1"
        call :clear_discord_cache "DiscordCanary.exe" "Discord Canary" "%APPDATA%\discordcanary"
    )
    if exist "%APPDATA%\discorddevelopment\" (
        set "discordFound=1"
        call :clear_discord_cache "DiscordDevelopment.exe" "Discord Development" "%APPDATA%\discorddevelopment"
    )
    if !discordFound! equ 0 call :PrintRed "Discord installations were not found"
    set "discordFound="
)
echo:

pause
goto menu


:: GAME SWITCH ========================
:game_switch_status
call :set_ui_codepage
set "gameFlagFile=%~dp0utils\game_filter.enabled"
set "GameFilterMode=disabled"
set "GameFilterTCPRange=1024-65535"
set "GameFilterUDPRange=1024-65535"
set "GameFilterStatus=disabled"
set "GameFilter=12"
set "GameFilterTCP=12"
set "GameFilterUDP=12"

if not exist "%gameFlagFile%" exit /b

set "GameFilterTCPCandidate="
set "GameFilterUDPCandidate="
for /f "usebackq tokens=1,* delims==" %%A in ("%gameFlagFile%") do (
    if /i "%%A"=="mode" set "GameFilterMode=%%B"
    if /i "%%A"=="all" set "GameFilterMode=all"
    if /i "%%A"=="udp" (
        if "%%B"=="" (set "GameFilterMode=udp") else set "GameFilterUDPCandidate=%%B"
    )
    if /i "%%A"=="tcp" (
        if "%%B"=="" (set "GameFilterMode=tcp") else set "GameFilterTCPCandidate=%%B"
    )
)

call :validate_game_filter_range "%GameFilterTCPCandidate%"
if defined ValidatedGameFilterRange set "GameFilterTCPRange=%ValidatedGameFilterRange%"
call :validate_game_filter_range "%GameFilterUDPCandidate%"
if defined ValidatedGameFilterRange set "GameFilterUDPRange=%ValidatedGameFilterRange%"

if /i "%GameFilterMode%"=="all" (
    set "GameFilterStatus=enabled (TCP and UDP)"
    set "GameFilter=%GameFilterTCPRange%"
    set "GameFilterTCP=%GameFilterTCPRange%"
    set "GameFilterUDP=%GameFilterUDPRange%"
) else if /i "%GameFilterMode%"=="tcp" (
    set "GameFilterStatus=enabled (TCP)"
    set "GameFilter=%GameFilterTCPRange%"
    set "GameFilterTCP=%GameFilterTCPRange%"
    set "GameFilterUDP=12"
) else if /i "%GameFilterMode%"=="udp" (
    set "GameFilterStatus=enabled (UDP)"
    set "GameFilter=%GameFilterUDPRange%"
    set "GameFilterTCP=12"
    set "GameFilterUDP=%GameFilterUDPRange%"
) else (
    set "GameFilterMode=disabled"
)
exit /b


:game_switch
call :set_ui_codepage
cls
call :game_switch_status

call :ui_echo "Select game filter option:" "Выберите параметр игрового фильтра:"
if "%GameFilterMode%"=="disabled"   (echo   1. * Disable) else      echo   1.   Disable
if "%GameFilterMode%"=="all"        (echo   2. * TCP and UDP) else  echo   2.   TCP and UDP
if "%GameFilterMode%"=="tcp"        (echo   3. * TCP) else          echo   3.   TCP
if "%GameFilterMode%"=="udp"        (echo   4. * UDP) else          echo   4.   UDP
echo.
call :ui_echo "   5. Change TCP port range (current: %GameFilterTCPRange%)" "   5. Изменить диапазон TCP-портов (сейчас: %GameFilterTCPRange%)"
call :ui_echo "   6. Change UDP port range (current: %GameFilterUDPRange%)" "   6. Изменить диапазон UDP-портов (сейчас: %GameFilterUDPRange%)"
call :ui_echo "   7. Change TCP and UDP port ranges" "   7. Изменить диапазоны TCP и UDP"
echo.
call :ui_echo "  0. Exit" "  0. Выход"
echo.
set "GameFilterChoice=0"
call :ui_prompt GameFilterChoice "Select option (0-7, default: 0): " "Выберите пункт (0–7, по умолчанию 0): "
if "%GameFilterChoice%"=="" set "GameFilterChoice=0"

if "%GameFilterChoice%"=="1" (
    set "GameFilterMode=disabled"
) else if "%GameFilterChoice%"=="2" (
    set "GameFilterMode=all"
) else if "%GameFilterChoice%"=="3" (
    set "GameFilterMode=tcp"
) else if "%GameFilterChoice%"=="4" (
    set "GameFilterMode=udp"
) else if "%GameFilterChoice%"=="5" (
    call :change_game_filter_range tcp
) else if "%GameFilterChoice%"=="6" (
    call :change_game_filter_range udp
) else if "%GameFilterChoice%"=="7" (
    call :change_game_filter_range all
) else (
    goto menu
)

echo.
call :save_game_filter_settings
call :ui_print PrintYellow "Restart the zapret to apply the changes" "Перезапустите zapret, чтобы применить изменения"
pause
goto game_switch


:change_game_filter_range
set "GameFilterRangeInput="

echo.
call :ui_echo "Changing ports for %~1 (example: 1024-1934,1936-65535, default: 1024-65535)" "Изменение портов для %~1 (пример: 1024-1934,1936-65535; по умолчанию: 1024-65535)"
call :ui_prompt GameFilterRangeInput "Enter ports/ranges: " "Введите порты/диапазоны: "
call :validate_game_filter_range "%GameFilterRangeInput%"
if not defined ValidatedGameFilterRange (
    call :ui_print PrintRed "Invalid input. Please enter valid ports/ranges." "Неверный ввод. Укажите корректные порты/диапазоны."
    pause
    goto game_switch
)

if /i "%~1"=="tcp" set "GameFilterTCPRange=%ValidatedGameFilterRange%"
if /i "%~1"=="udp" set "GameFilterUDPRange=%ValidatedGameFilterRange%"
if /i "%~1"=="all" (
    set "GameFilterTCPRange=%ValidatedGameFilterRange%"
    set "GameFilterUDPRange=%ValidatedGameFilterRange%"
)
exit /b


:validate_game_filter_range
set "ValidatedGameFilterRange="
setlocal EnableDelayedExpansion
set "GameFilterRangeToValidate=%~1"
set "GameFilterRangeToValidate=!GameFilterRangeToValidate: =!"
if not defined GameFilterRangeToValidate exit /b
for %%A in ("!GameFilterRangeToValidate:,=" "!") do (
    call :gf_validate_item "%%~A"
    if not defined GameFilterRangeItemValid exit /b
)
endlocal & set "ValidatedGameFilterRange=%GameFilterRangeToValidate%"
exit /b


:gf_validate_item
set "GameFilterRangeItemValid="
setlocal EnableDelayedExpansion
set "GameFilterRangeItem=%~1"

echo(!GameFilterRangeItem!| findstr /r /x /c:"[1-9][0-9]*" /c:"[1-9][0-9]*-[1-9][0-9]*" > nul || exit /b
for /f "tokens=1,2 delims=-" %%A in ("!GameFilterRangeItem!") do (
    set "GameFilterRangeStart=%%A"
    set "GameFilterRangeEnd=%%B"
)
if not defined GameFilterRangeEnd set "GameFilterRangeEnd=!GameFilterRangeStart!"

if not "!GameFilterRangeStart:~5,1!"=="" exit /b
if not "!GameFilterRangeEnd:~5,1!"=="" exit /b
set /a GameFilterRangeStartNumber=GameFilterRangeStart, GameFilterRangeEndNumber=GameFilterRangeEnd
if !GameFilterRangeStartNumber! gtr 65535 exit /b
if !GameFilterRangeEndNumber! gtr 65535 exit /b
if !GameFilterRangeStartNumber! gtr !GameFilterRangeEndNumber! exit /b

endlocal & set "GameFilterRangeItemValid=1"
exit /b


:save_game_filter_settings
>"%gameFlagFile%" (
    echo mode=%GameFilterMode%
    echo tcp=%GameFilterTCPRange%
    echo udp=%GameFilterUDPRange%
)
exit /b


:: CUSTOM FIX FILTERS ===================
:load_fix_settings
set "fixFiltersFile=%~dp0utils\fix_filters.ini"
set "WarpFilterEnabled=1"
set "MinecraftFilterEnabled=1"
set "AutoStrategyEnabled=0"
set "AutoHostlistEnabled=0"

if not exist "%fixFiltersFile%" (
    >"%fixFiltersFile%" (
        echo warp=1
        echo minecraft=1
        echo autostrategy=0
        echo autohostlist=0
    )
)

for /f "usebackq tokens=1,* delims==" %%A in ("%fixFiltersFile%") do (
    if /i "%%A"=="warp" set "WarpFilterEnabled=%%B"
    if /i "%%A"=="minecraft" set "MinecraftFilterEnabled=%%B"
    if /i "%%A"=="autostrategy" set "AutoStrategyEnabled=%%B"
    if /i "%%A"=="autohostlist" set "AutoHostlistEnabled=%%B"
)

if not "%WarpFilterEnabled%"=="0" if not "%WarpFilterEnabled%"=="1" set "WarpFilterEnabled=1"
if not "%MinecraftFilterEnabled%"=="0" if not "%MinecraftFilterEnabled%"=="1" set "MinecraftFilterEnabled=1"
if not "%AutoStrategyEnabled%"=="0" if not "%AutoStrategyEnabled%"=="1" set "AutoStrategyEnabled=0"
if not "%AutoHostlistEnabled%"=="0" if not "%AutoHostlistEnabled%"=="1" set "AutoHostlistEnabled=0"

set "WarpFilterWF="
set "WarpFilterSkip=--skip"
if "%WarpFilterEnabled%"=="1" set "WarpFilterWF=,500,1701,4500,8095,2408"
if "%WarpFilterEnabled%"=="1" set "WarpFilterSkip="

set "MinecraftFilterWF="
set "MinecraftFilterSkip=--skip"
if "%MinecraftFilterEnabled%"=="1" set "MinecraftFilterWF=,25565"
if "%MinecraftFilterEnabled%"=="1" set "MinecraftFilterSkip="

set "AutoHostlistSkip=--skip"
if "%AutoHostlistEnabled%"=="1" set "AutoHostlistSkip="
if not exist "%~dp0lists\hostlist-auto.txt" (
    if exist "%~dp0lists\hostlist-auto.txt.example" (
        copy /y "%~dp0lists\hostlist-auto.txt.example" "%~dp0lists\hostlist-auto.txt" >nul
    ) else (
        type nul > "%~dp0lists\hostlist-auto.txt"
    )
)
exit /b


:update_status_labels
set "GameFilterStatusDisplay=!GameFilterStatus!"
set "IPsetStatusDisplay=!IPsetStatus!"
set "CheckUpdatesStatusDisplay=!CheckUpdatesStatus!"
set "WarpFilterStatusDisplay=!WarpFilterStatus!"
set "MinecraftFilterStatusDisplay=!MinecraftFilterStatus!"
set "AutoStrategyStatusDisplay=!AutoStrategyStatus!"
set "AutoHostlistStatusDisplay=!AutoHostlistStatus!"
if /i "%UI_LANG%"=="ru" (
    if /i "!GameFilterStatus!"=="enabled" set "GameFilterStatusDisplay=включён"
    if /i "!GameFilterStatus!"=="disabled" set "GameFilterStatusDisplay=выключен"
    if /i "!IPsetStatus!"=="loaded" set "IPsetStatusDisplay=загружен"
    if /i "!IPsetStatus!"=="none" set "IPsetStatusDisplay=ограничен"
    if /i "!IPsetStatus!"=="any" set "IPsetStatusDisplay=все IP"
    if /i "!CheckUpdatesStatus!"=="enabled" set "CheckUpdatesStatusDisplay=включена"
    if /i "!CheckUpdatesStatus!"=="disabled" set "CheckUpdatesStatusDisplay=выключена"
    if /i "!WarpFilterStatus!"=="enabled" set "WarpFilterStatusDisplay=включён"
    if /i "!WarpFilterStatus!"=="disabled" set "WarpFilterStatusDisplay=выключен"
    if /i "!MinecraftFilterStatus!"=="enabled" set "MinecraftFilterStatusDisplay=включён"
    if /i "!MinecraftFilterStatus!"=="disabled" set "MinecraftFilterStatusDisplay=выключен"
    if /i "!AutoStrategyStatus!"=="enabled" set "AutoStrategyStatusDisplay=включён"
    if /i "!AutoStrategyStatus!"=="disabled" set "AutoStrategyStatusDisplay=выключен"
    if /i "!AutoHostlistStatus!"=="enabled" set "AutoHostlistStatusDisplay=включён"
    if /i "!AutoHostlistStatus!"=="disabled" set "AutoHostlistStatusDisplay=выключен"
)
exit /b


:fix_filters_status
call :load_fix_settings
if "%WarpFilterEnabled%"=="1" (set "WarpFilterStatus=enabled") else set "WarpFilterStatus=disabled"
if "%MinecraftFilterEnabled%"=="1" (set "MinecraftFilterStatus=enabled") else set "MinecraftFilterStatus=disabled"
if "%AutoStrategyEnabled%"=="1" (set "AutoStrategyStatus=enabled") else set "AutoStrategyStatus=disabled"
if "%AutoHostlistEnabled%"=="1" (set "AutoHostlistStatus=enabled") else set "AutoHostlistStatus=disabled"
exit /b


:save_fix_filters
>"%fixFiltersFile%" (
    echo warp=%WarpFilterEnabled%
    echo minecraft=%MinecraftFilterEnabled%
    echo autostrategy=%AutoStrategyEnabled%
    echo autohostlist=%AutoHostlistEnabled%
)
exit /b


:fix_filters_menu
chcp 65001 > nul
cls
call :fix_filters_status
call :update_status_labels

call :ui_echo "CUSTOM FIX FILTERS" "ДОПОЛНИТЕЛЬНЫЕ ФИКСЫ"
echo.
call :ui_echo "   1. Toggle WARP UDP ports [!WarpFilterStatus!]" "   1. Включить/выключить UDP-порты WARP [!WarpFilterStatusDisplay!]"
call :ui_echo "      Ports: UDP 500, 1701, 4500, 8095, 2408" "      Порты: UDP 500, 1701, 4500, 8095, 2408"
call :ui_echo "   2. Toggle Minecraft servers [!MinecraftFilterStatus!]" "   2. Включить/выключить фильтр Minecraft [!MinecraftFilterStatusDisplay!]"
call :ui_echo "      TCP/25565, IP list and domains from minecraft-domains.txt" "      TCP/25565, IP-список и домены из minecraft-domains.txt"
call :ui_echo "   3. Refresh Minecraft domain IP addresses" "   3. Обновить IP-адреса доменов Minecraft"
call :ui_echo "   4. Auto-pick strategy while idle [!AutoStrategyStatus!]" "   4. Автоподбор стратегии в простое [!AutoStrategyStatusDisplay!]"
call :ui_echo "      Tests strategies only after 15 minutes of user inactivity" "      Проверка после 15 минут бездействия пользователя"
call :ui_echo "   5. AutoHostlist [!AutoHostlistStatus!]" "   5. AutoHostlist [!AutoHostlistStatusDisplay!]"
call :ui_echo "      Dynamically learns blocked TCP/443 domains into hostlist-auto.txt" "      Автоматически добавляет заблокированные домены TCP/443 в hostlist-auto.txt"
echo.
call :ui_echo "   0. Back" "   0. Назад"
echo.
set "FixFiltersChoice=0"
call :ui_prompt FixFiltersChoice "Select option (0-5, default: 0): " "Выберите пункт (0–5, по умолчанию 0): "
if "!FixFiltersChoice!"=="1" (
    if "!WarpFilterEnabled!"=="1" (set "WarpFilterEnabled=0") else set "WarpFilterEnabled=1"
    call :save_fix_filters
    call :apply_fix_filter_changes
    goto fix_filters_menu
)
if "!FixFiltersChoice!"=="2" (
    if "!MinecraftFilterEnabled!"=="1" (set "MinecraftFilterEnabled=0") else set "MinecraftFilterEnabled=1"
    call :save_fix_filters
    call :apply_fix_filter_changes
    goto fix_filters_menu
)
if "!FixFiltersChoice!"=="3" (
    call :refresh_minecraft_domains
    call :ui_print PrintGreen "Resolved Minecraft domain IP addresses: !MinecraftResolvedCount!" "Количество разрешённых IP-адресов Minecraft-доменов: !MinecraftResolvedCount!"
    pause
    goto fix_filters_menu
)
if "!FixFiltersChoice!"=="4" (
    if "!AutoStrategyEnabled!"=="1" (set "AutoStrategyEnabled=0") else set "AutoStrategyEnabled=1"
    call :save_fix_filters
    call :manage_auto_strategy_task
    goto fix_filters_menu
)
if "!FixFiltersChoice!"=="5" (
    if "!AutoHostlistEnabled!"=="1" (set "AutoHostlistEnabled=0") else set "AutoHostlistEnabled=1"
    call :save_fix_filters
    call :apply_fix_filter_changes
    goto fix_filters_menu
)
if "!FixFiltersChoice!"=="0" goto menu
goto fix_filters_menu


:manage_auto_strategy_task
if "%AutoStrategyEnabled%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\manage-auto-strategy-task.ps1" -Action Enable
    if errorlevel 1 (
        set "AutoStrategyEnabled=0"
        call :save_fix_filters
        call :ui_print PrintRed "Could not register the idle auto-strategy task; it has been disabled." "Не удалось зарегистрировать задачу автоподбора стратегии; функция отключена."
    ) else (
        call :ui_print PrintGreen "Idle auto-strategy task enabled. It checks every 30 minutes." "Автоподбор стратегии в простое включён. Проверка запускается каждые 30 минут."
    )
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\manage-auto-strategy-task.ps1" -Action Disable
    if errorlevel 1 (
        call :ui_print PrintYellow "Could not remove the idle auto-strategy task." "Не удалось удалить задачу автоподбора стратегии."
    ) else (
        call :ui_print PrintGreen "Idle auto-strategy task disabled." "Автоподбор стратегии в простое отключён."
    )
)
pause
exit /b


:apply_fix_filter_changes
call :load_fix_settings
echo.
call :ui_print PrintGreen "Custom fix settings saved." "Настройки дополнительных фиксов сохранены."
sc query "zapret" >nul 2>&1
if !errorlevel! equ 0 (
    set "RebuildFixService=Y"
    call :ui_prompt RebuildFixService "Zapret service is installed. Rebuild it now with these settings? (Y/N, default Y): " "Zapret установлена как служба. Пересобрать её с этими настройками? (Y/N, по умолчанию Y): "
    if "!RebuildFixService!"=="" set "RebuildFixService=Y"
    if /i "!RebuildFixService!"=="Y" goto service_install_existing
    call :ui_print PrintYellow "The installed service keeps its previous arguments until rebuilt." "Установленная служба сохранит прежние параметры, пока её не пересобрать."
) else (
    call :ui_print PrintYellow "Restart any running general*.bat strategy to apply the new settings." "Перезапустите запущенную стратегию general*.bat, чтобы применить новые настройки."
)
pause
exit /b


:refresh_minecraft_domains
set "MinecraftResolvedCount=0"
for /f "delims=" %%N in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\refresh-minecraft-domains.ps1" 2^>nul') do set "MinecraftResolvedCount=%%N"
if not exist "%~dp0lists\minecraft-domains-resolved.txt" type nul > "%~dp0lists\minecraft-domains-resolved.txt"
exit /b


:: CHECK UPDATES SWITCH =================
:check_updates_switch_status
call :set_ui_codepage
set "checkUpdatesFlag=%~dp0utils\check_updates.enabled"

if exist "%checkUpdatesFlag%" (
    set "CheckUpdatesStatus=enabled"
) else (
    set "CheckUpdatesStatus=disabled"
)
exit /b


:check_updates_switch
call :set_ui_codepage
cls

if not exist "%checkUpdatesFlag%" (
    call :ui_echo "Enabling check updates..." "Включение проверки обновлений..."
    echo ENABLED > "%checkUpdatesFlag%"
) else (
    call :ui_echo "Disabling check updates..." "Отключение проверки обновлений..."
    del /f /q "%checkUpdatesFlag%"
)

pause
goto menu


:: REPLACE ACTIVE FAKES =================
:replace_active_fakes
call :set_ui_codepage
cls

set "BIN_PATH=%~dp0bin\"
set "fake_count=0"
set "fake_type="
set "fake_number="
set "discord_hash="
set "game_hash="
set "current_discord_fake=(not found)"
set "current_game_fake=(not found)"

if not exist "%BIN_PATH%" (
    call :ui_echo "Error: bin folder not found." "Ошибка: папка bin не найдена."
    pause
    goto menu
)

pushd "%BIN_PATH%"
for /f "tokens=1,2,3 delims=|" %%A in ('powershell -NoProfile -Command "foreach ($item in @(@{Name='ACTIVE_DISCORD_UDP.bin'; Label='ACTIVE_DISCORD'},@{Name='ACTIVE_GAME_UDP.bin'; Label='ACTIVE_GAME'})) { if (Test-Path -LiteralPath $item.Name) { Write-Output ($item.Label + [char]124 + $item.Label + [char]124 + (Get-FileHash -LiteralPath $item.Name -Algorithm SHA256).Hash) } }; $files = @(Get-ChildItem -LiteralPath . -File -Filter '*.bin'); foreach ($file in $files) { if ($file.BaseName -notlike 'ACTIVE_*') { Write-Output ('FAKE' + [char]124 + $file.BaseName + [char]124 + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) } }"') do (
    if "%%A"=="ACTIVE_DISCORD" (
        set "discord_hash=%%C"
    ) else if "%%A"=="ACTIVE_GAME" (
        set "game_hash=%%C"
    ) else if "%%A"=="FAKE" (
        set /a fake_count+=1
        set "fake_file!fake_count!=%BIN_PATH%%%B.bin"
        set "fake_name!fake_count!=%%B"
        set "fake_hash!fake_count!=%%C"
    )
)
popd

if !fake_count! EQU 0 (
    call :ui_echo "No .bin files were found in the bin folder." "В папке bin не найдено файлов .bin."
    pause
    goto menu
)

for /l %%N in (1,1,!fake_count!) do (
    if defined discord_hash if /i "!fake_hash%%N!"=="!discord_hash!" set "current_discord_fake=!fake_name%%N!"
    if defined game_hash if /i "!fake_hash%%N!"=="!game_hash!" set "current_game_fake=!fake_name%%N!"
)

:replace_active_fakes_prompt
echo.
call :ui_echo "Enter the fake type number and the fake file number to replace it with." "Введите номер типа фейка и номер файла, на который его заменить."
call :ui_echo "Example: 1 4 (replaces Discord UDP with fake file under number 4)" "Пример: 1 4 (заменить Discord UDP фейком под номером 4)"
call :ui_echo "          2 1 (replaces GameFilter UDP with fake file under number 1)" "          2 1 (заменить GameFilter UDP фейком под номером 1)"
echo.
call :ui_echo "Press ENTER or 0 to return." "Нажмите ENTER или 0 для возврата."
echo.
call :ui_echo "   ----------------------------------------" "   ----------------------------------------"
echo.
call :ui_echo "Fake types:" "Типы фейков:"
call :ui_echo "   1. Discord UDP     (current: !current_discord_fake!)" "   1. Discord UDP     (сейчас: !current_discord_fake!)"
call :ui_echo "   2. GameFilter UDP  (current: !current_game_fake!)" "   2. GameFilter UDP  (сейчас: !current_game_fake!)"
echo.
call :ui_echo "Fake files:" "Файлы фейков:"
for /l %%N in (1,1,!fake_count!) do echo   %%N. !fake_name%%N!
echo.

set "replace_choice="
call :ui_prompt replace_choice "Enter choice: " "Введите выбор: "
if not defined replace_choice goto menu
if "!replace_choice!"=="0" goto menu

set "active_file="
set "fake_type="
set "fake_number="
for /f "tokens=1,2" %%A in ("!replace_choice!") do (
    set "fake_type=%%A"
    set "fake_number=%%B"
)

if "!fake_type!"=="1" (
    set "active_file=%BIN_PATH%ACTIVE_DISCORD_UDP.bin"
) else if "!fake_type!"=="2" (
    set "active_file=%BIN_PATH%ACTIVE_GAME_UDP.bin"
) else (
    call :ui_echo "Invalid fake type." "Неверный тип фейка."
    pause
    cls
    goto replace_active_fakes_prompt
)

set "source_file="
for /l %%N in (1,1,!fake_count!) do if "%%N"=="!fake_number!" set "source_file=!fake_file%%N!"
if not defined source_file (
    call :ui_echo "Invalid fake file number." "Неверный номер файла фейка."
    pause
    cls
    goto replace_active_fakes_prompt
)

del /f /q "!active_file!" >nul 2>&1
copy /y "!source_file!" "!active_file!" >nul
if errorlevel 1 (
    call :ui_echo "Failed to replace the active fake file." "Не удалось заменить активный файл фейка."
) else (
    call :ui_echo "Active fake file replaced successfully." "Активный файл фейка успешно заменён."
    for /l %%N in (1,1,!fake_count!) do if "%%N"=="!fake_number!" (
        if "!fake_type!"=="1" set "current_discord_fake=!fake_name%%N!"
        if "!fake_type!"=="2" set "current_game_fake=!fake_name%%N!"
    )
)
pause
cls
goto replace_active_fakes_prompt


:: IPSET SWITCH =======================
:ipset_switch_status
call :set_ui_codepage
set "listFile=%~dp0lists\ipset-all.txt"
for /f %%i in ('type "%listFile%" 2^>nul ^| find /c /v ""') do set "lineCount=%%i"

if !lineCount!==0 (
    set "IPsetStatus=any"
) else (
    findstr /C:"203.0.113.113/32" "%listFile%" >nul
    if !errorlevel!==0 (
        set "IPsetStatus=none"
    ) else (
        set "IPsetStatus=loaded"
    )
)
exit /b


:ipset_switch
call :set_ui_codepage
cls

set "listFile=%~dp0lists\ipset-all.txt"
set "backupFile=%listFile%.backup"

if "%IPsetStatus%"=="loaded" (
    call :ui_echo "Switching to none mode..." "Переключение в режим none..."
    
    if not exist "%backupFile%" (
        ren "%listFile%" "ipset-all.txt.backup"
    ) else (
        del /f /q "%backupFile%"
        ren "%listFile%" "ipset-all.txt.backup"
    )
    
    >"%listFile%" (
        echo 203.0.113.113/32
    )
    
) else if "%IPsetStatus%"=="none" (
    call :ui_echo "Switching to any mode..." "Переключение в режим any..."
    
    >"%listFile%" (
        rem Creating empty file
    )
    
) else if "%IPsetStatus%"=="any" (
    call :ui_echo "Switching to loaded mode..." "Переключение в режим loaded..."
    
    if exist "%backupFile%" (
        del /f /q "%listFile%"
        ren "%backupFile%" "ipset-all.txt"
    ) else (
        call :ui_echo "Error: no backup to restore. Update list from service menu first" "Ошибка: резервная копия отсутствует. Сначала обновите список через меню службы"
        pause
        goto menu
    )
    
)

pause
goto menu


:: IPSET UPDATE =======================
:ipset_update
call :set_ui_codepage
cls

set "listFile=%~dp0lists\ipset-all.txt"
set "url=https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt"

call :ui_echo "Updating ipset-all..." "Обновление ipset-all..."

if exist "%SystemRoot%\System32\curl.exe" (
    curl --version | find "libcurl/7"
    if !errorlevel!==0 (
        curl --ssl-no-revoke -L -f -o "%listFile%" "%url%"
    ) else (
        curl --ssl-revoke-best-effort -L -f -o "%listFile%" "%url%"
    )
) else (
    powershell -NoProfile -Command ^
        "$url = '%url%';" ^
        "$out = '%listFile%';" ^
        "$dir = Split-Path -Parent $out;" ^
        "if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null };" ^
        "$res = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing;" ^
        "if ($res.StatusCode -eq 200) { $res.Content | Out-File -FilePath $out -Encoding UTF8 } else { exit 1 }"
)

call :ui_echo "Finished" "Завершено"

pause
goto menu


:: HOSTS UPDATE =======================
:hosts_update
call :set_ui_codepage
cls

set "hostsFile=%SystemRoot%\System32\drivers\etc\hosts"
set "hostsUrl=https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/hosts"
set "tempFile=%TEMP%\zapret_hosts.txt"
set "needsUpdate=0"

set "cacheBuster=%RANDOM%%RANDOM%%RANDOM%"
set "requestUrl=%hostsUrl%?t=%cacheBuster%"

call :ui_echo "Checking hosts file..." "Проверка файла Hosts..."

if exist "%SystemRoot%\System32\curl.exe" (
    curl -L -s -f -o "%tempFile%" "%requestUrl%"
) else (
    powershell -NoProfile -Command ^
        "$url = '%requestUrl%';" ^
        "$out = '%tempFile%';" ^
        "$res = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing;" ^
        "if ($res.StatusCode -eq 200) { $res.Content | Out-File -FilePath $out -Encoding UTF8 } else { exit 1 }"
)
if not exist "%tempFile%" (
    call :ui_print PrintRed "Failed to download hosts file from repository" "Не удалось загрузить файл Hosts из репозитория"
    call :ui_print PrintYellow "Copy hosts file manually from %hostsUrl%" "Скопируйте файл Hosts вручную отсюда: %hostsUrl%"
    pause
    goto menu
)

set "firstLine="
set "lastLine="
for /f "usebackq delims=" %%a in ("%tempFile%") do (
    if not defined firstLine (
        set "firstLine=%%a"
    )
    set "lastLine=%%a"
)

findstr /C:"!firstLine!" "%hostsFile%" >nul 2>&1
if !errorlevel! neq 0 (
    call :ui_echo "First line from repository not found in hosts file" "Первая строка из репозитория не найдена в файле Hosts"
    set "needsUpdate=1"
)

findstr /C:"!lastLine!" "%hostsFile%" >nul 2>&1
if !errorlevel! neq 0 (
    call :ui_echo "Last line from repository not found in hosts file" "Последняя строка из репозитория не найдена в файле Hosts"
    set "needsUpdate=1"
)

if "%needsUpdate%"=="1" (
    echo:
    call :ui_print PrintYellow "Hosts file needs to be updated" "Файл Hosts необходимо обновить"
    call :ui_print PrintYellow "Please manually copy the content from the downloaded file to your hosts file" "Скопируйте содержимое загруженного файла в системный файл Hosts вручную"
    
    start notepad "%tempFile%"
    explorer /select,"%hostsFile%"
) else (
    call :ui_print PrintGreen "Hosts file is up to date" "Файл Hosts актуален"
    if exist "%tempFile%" del /f /q "%tempFile%"
)

echo:
pause
goto menu


:: RUN TESTS =============================
:run_tests
call :set_ui_codepage
cls

:: Require PowerShell 3.0+
powershell -NoProfile -Command "if ($PSVersionTable -and $PSVersionTable.PSVersion -and $PSVersionTable.PSVersion.Major -ge 3) { exit 0 } else { exit 1 }" >nul 2>&1
if %errorLevel% neq 0 (
    call :ui_echo "PowerShell 3.0 or newer is required." "Требуется PowerShell 3.0 или новее."
    call :ui_echo "Please upgrade PowerShell and rerun this script." "Обновите PowerShell и запустите этот скрипт повторно."
    echo.
    pause
    goto menu
)

call :ui_echo "Starting configuration tests in PowerShell window..." "Запуск тестирования конфигураций в окне PowerShell..."
echo.
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\test zapret.ps1"
pause
goto menu


:: Get strategy name
:get_strategy_name
set "CurrentStrategy="
for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube 2^>nul') do (
    if /i "!UI_LANG!"=="ru" (set "CurrentStrategy=Стратегия: %%B") else set "CurrentStrategy=Strategy: %%B"
)
exit /b


:: Utility functions

:clear_discord_cache
setlocal EnableDelayedExpansion
set "discordProcess=%~1"
set "discordName=%~2"
set "discordCacheDir=%~3"

tasklist /FI "IMAGENAME eq !discordProcess!" 2>nul | findstr /I /C:"!discordProcess!" >nul
if !errorlevel! equ 0 (
    call :ui_echo " !discordName! is running, closing..." " !discordName! запущен, закрытие..."
    taskkill /IM "!discordProcess!" /F >nul 2>&1
    if !errorlevel! equ 0 (
        call :ui_print PrintGreen "!discordName! was successfully closed" "!discordName! успешно закрыт"
    ) else (
        call :ui_print PrintRed "Unable to close !discordName!" "Не удалось закрыть !discordName!"
    )
)

if exist "!discordCacheDir!\" (
    for %%d in ("Cache" "Code Cache" "GPUCache") do (
        set "dirPath=!discordCacheDir!\%%~d"
        if exist "!dirPath!\" (
            rd /s /q "!dirPath!" >nul 2>&1
            if exist "!dirPath!\" (
                call :ui_print PrintRed "Failed to delete !dirPath!" "Не удалось удалить !dirPath!"
            ) else (
                call :ui_print PrintGreen "Successfully deleted !dirPath!" "Успешно удалено: !dirPath!"
            )
        ) else (
            call :ui_print PrintRed "!dirPath! does not exist" "Путь !dirPath! не существует"
        )
    )
)

endlocal
exit /b

:PrintGreen
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Green"
exit /b

:PrintRed
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Red"
exit /b

:PrintYellow
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Yellow"
exit /b

:check_command
where %1 >nul 2>&1
if %errorLevel% neq 0 (
    call :ui_echo "[ERROR] %1 not found in PATH" "[ОШИБКА] %1 не найден в PATH"
    call :ui_echo "Fix your PATH variable with instructions here https://github.com/Flowseal/zapret-discord-youtube/issues/7490" "Исправьте переменную PATH по инструкции: https://github.com/Flowseal/zapret-discord-youtube/issues/7490"
    pause
    exit /b 1
)
exit /b 0

:check_extracted
set "extracted=1"

if not exist "%~dp0bin\" set "extracted=0"

if "%extracted%"=="0" (
    call :ui_echo "Zapret must be extracted from archive first or bin folder not found for some reason" "Сначала распакуйте Zapret из архива или проверьте наличие папки bin"
    pause
    exit
)
exit /b 0


:external_load_fix_settings
call :load_fix_settings
if "%MinecraftFilterEnabled%"=="1" call :refresh_minecraft_domains
exit /b


:external_install_strategy_auto
if /i not "%~3"=="admin" exit /b 2
setlocal EnableDelayedExpansion
cd /d "%~dp0"
set "BIN_PATH=%~dp0bin\"
set "LISTS_PATH=%~dp0lists\"
call :load_user_lists
set "selectedFile="
for %%F in ("%~dp0general*.bat") do (
    if /i "%%~nxF"=="%~2" set "selectedFile=%%~fF"
)
if not defined selectedFile exit /b 2
set "AUTO_INSTALL_NONINTERACTIVE=1"
goto service_install_prepare


:set_ui_codepage
if /i "%UI_LANG%"=="ru" (chcp 65001 >nul) else (chcp 437 >nul)
exit /b

:ui_echo
set "UI_MSG_EN=%~1"
set "UI_MSG_RU=%~2"
if /i "%UI_LANG%"=="ru" (echo(%UI_MSG_RU%) else echo(%UI_MSG_EN%)
exit /b

:ui_print
set "UI_COLOR=%~1"
set "UI_MSG_EN=%~2"
set "UI_MSG_RU=%~3"
if /i "%UI_LANG%"=="ru" (call :%UI_COLOR% "%UI_MSG_RU%") else call :%UI_COLOR% "%UI_MSG_EN%"
exit /b

:ui_prompt
set "UI_PROMPT_EN=%~2"
set "UI_PROMPT_RU=%~3"
if /i "%UI_LANG%"=="ru" (set "UI_PROMPT=%UI_PROMPT_RU%") else set "UI_PROMPT=%UI_PROMPT_EN%"
set /p "%~1=%UI_PROMPT%"
exit /b
