==========
= Tundra =
==========


Tundra is a 16-bit fantasy computer architecture where every instruction is 1
byte by default. For more details, see the docs directory.

Emulator
========

Compiling
---------
Tundra may be compiled via the zig master branch.

  zig build -Doptimize=ReleaseSafe

Usage
-----
  tundra <memory_file> [[-s storage_file] ...] [-d]

Usage Notes
-----------
- if the '-d' flag is set, each instruction will be printed as it is run

Assembler
=========

Tundra assembly files may be assembled with fasmg (https://flatassembler.net/).
see docs/assembly.txt for more information.

Disassembler
============

Assembled Tundra programs may be disassembled with the Tundra disassembler.

Compiling
---------
The Tundra disassembler may be compiled with the Zig master branch.

  cd disassem
  zig build -Doptimize=ReleaseSafe

Usage
-----
  usage: disassem <memory_file> [[--data <range>]...]

Usage Notes
-----------
- the '--data' option is used to mark a region of the file as data and not code
- ranges are of the form '<start>-<end>' (inclusive), where start is less than end
- start and end must both be up to 4 digits of hexadecimal

License
=======

- the contents of this repository are licensed under the 3-Clause BSD license
  unless otherwise specified
- tundra-core.inc and tundra-extra.inc are licensed under the 0-Clause BSD
  license
