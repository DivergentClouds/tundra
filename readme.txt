==========
= Tundra =
==========


Tundra is a 16-bit fantasy computer architecture where every instruction is 1
byte by default. For more details, see the docs directory.

Emulator
========

Assembled Tundra programs may be run with the Tundra emulator.

Compiling
---------
The Tundra emulator may be compiled with Zig 0.14.0.

  cd emu
  zig build -Doptimize=ReleaseSafe

Usage
-----
  tundra <rom_file> [[-s storage_file] ...] [-d]

Usage Notes
-----------
- if the '-d' flag is set, debug mode will be activated
  - debug mode is not currently implemented
- rom files may be at most 12 KiB

Assembler
=========

Tundra assembly files may be assembled with fasmg (https://flatassembler.net/).
See docs/assembly.txt for more information.

Disassembler
============

Assembled Tundra programs may be disassembled with the Tundra disassembler.

Compiling
---------
The Tundra disassembler may be compiled with Zig 0.14.0.

  cd disassem
  zig build -Doptimize=ReleaseSafe

Usage
-----
  usage: tundis <memory_file> [[--data <range>]...]

Usage Notes
-----------
- the '--data' option is used to mark a region of the file as data and not code
- ranges are of the form '<start>-<end>' (inclusive), where start is less than
  or equal to end
- start and end must both be up to 4 digits of hexadecimal

License
=======

- the contents of this repository are licensed under the 3-Clause BSD license
  unless otherwise specified
- tundra-core.inc and tundra-extra.inc are licensed under the 0-Clause BSD
  license
