@echo off & setlocal EnableDelayedExpansion
echo [SimSymSrv] Building...
zig build-exe src/main.zig -O ReleaseFast -target x86_64-windows -fstrip -femit-bin="SimSymSrv.exe"
echo [SimSymSrv] Done.
