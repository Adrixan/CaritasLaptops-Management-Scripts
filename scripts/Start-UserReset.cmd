@echo off
setlocal
chcp 65001 >nul
title Caritas Laptops - Sitzung zurücksetzen
cls
echo ============================================================
echo      CARITAS LAPTOPS - SITZUNG ZURÜCKSETZEN
echo ============================================================
echo.
echo Die Sitzung des Benutzers 'User' wird jetzt zurückgesetzt.
echo Alle persönlichen Dokumente, Downloads, der Browserverlauf
echo und der Papierkorb werden vollständig bereinigt.
echo.
echo Das Gerät startet anschließend automatisch neu.
echo.
echo ------------------------------------------------------------
echo Starte geplante Aufgabe 'Caritas-ResetUserSession'...
schtasks.exe /run /tn "Caritas-ResetUserSession"
if %ERRORLEVEL% EQU 0 (
    echo.
    echo [OK] Zurücksetzung erfolgreich eingeleitet.
    echo Das System startet in wenigen Sekunden neu...
    timeout /t 3 /nobreak >nul
) else (
    echo.
    echo [FEHLER] Die geplante Aufgabe konnte nicht gestartet werden!
    echo Fehlercode: %ERRORLEVEL%
    echo.
    echo Bitte wenden Sie sich an die Caritas IT-Administration.
    echo.
    pause
)
endlocal
