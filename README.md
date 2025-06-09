# SimSymSrv
![Zig](https://img.shields.io/badge/Zig-%23F7A41D.svg?style=for-the-badge&logo=zig&logoColor=white)

<p align="center">
<img src="https://pics.clipartpng.com/Ladybug_PNG_Clip_Art-1582.png" height="200" width="auto"><br>
SimSymSrv - Simple Symbol Server Downloader <br>
<sub><i>I shouldn't be allowed to name things...</i></sub>
</p>

---

## What is this?
This is a simple CLI tool to download official Microsoft Debugging Symbols <br>
from the Microsoft Symbol Server ([SymSrv](https://msdl.microsoft.com/download/symbols))

- You provide a Microsoft Binary (EXE / DLL / SYS)
- You provide a directory
- It downloads the debugging symbols to that directory

Simple as that.

![image](https://github.com/user-attachments/assets/abd85054-a525-461a-b37a-0a74e61640ca)

Can also be used with CLI Arguments now, See `simsymsrv --help`

```
SimSymSrv is a tool to download PDB files from Microsoft's Symbol Server.
Copyright (c) 2025 NullDev

Usage: SimSymSrv [options]

Options:
  -i, --input <PATH>   Path to EXE/DLL/SYS file
  -o, --output <PATH>  Path to output folder
  -h, --help           Print this help message

If options are not provided, you will be prompted for the missing input.
```

---

## Why? 
So you can reverse and debug official MS binaries. Yay...

---

## Download

Binaries can be downloaded from [releases](https://github.com/NullDev/SimSymSrv/releases)

---

## From Source

- `git clone https://github.com/NullDev/SimSymSrv.git && cd SimSymSrv`
- Dev
  - `zig run .\src\main.zig`
  - Or with CLI options, e.g.: `zig run .\src\main.zig -- --help`
- Release
  - `zig build-exe src/main.zig -O ReleaseFast -target x86_64-windows -fstrip -femit-bin="SimSymSrv.exe"`

---

## Note
This is still in its rough stages, and it's also my very first Zig project...
