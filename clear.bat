@echo off

:: Usuwanie zawartości z 'C:\Windows\Temp'
del /q /f "C:\Windows\Temp\*.*"
for /d %%i in ("C:\Windows\Temp\*") do rd /s /q "%%i"

:: Usuwanie zawartości z '%temp%'
del /q /f "%temp%\*.*"
for /d %%i in ("%temp%\*") do rd /s /q "%%i"

:: Usuwanie zawartości z 'C:\Windows\Prefetch'
del /q /f "C:\Windows\Prefetch\*.*"
for /d %%i in ("C:\Windows\Prefetch\*") do rd /s /q "%%i"