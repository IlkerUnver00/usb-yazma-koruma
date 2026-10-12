@echo off
rem USB yazma korumasi - menuyu acar. Yonetici izni (UAC) istenir.
rem Menusuz kullanim: UsbYazmaKorumasi.cmd -Islem Ac ^| Kapat ^| Durum ^| Test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UsbYazmaKorumasi.ps1" %*
