@echo off
rem ====================================================================
rem  La Grande Vision - lanceur
rem  Demarre le serveur local puis ouvre l'application dans le navigateur.
rem  Double-cliquez sur ce fichier pour utiliser l'application.
rem ====================================================================
title Lanceur La Grande Vision
cd /d "%~dp0"
start "Serveur La Grande Vision - NE PAS FERMER" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
exit
