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

Notes
-----
- if the '-d' flag is set, each instruction will be printed as it is run

Assembler
=========
Tundra assembly files may be assembled with fasmg (https://flatassembler.net/).
see docs/assembly.txt for more information.

License
=======

- the contents of this repository are licensed under the 3-Clause BSD license
  unless otherwise specified
- tundra-core.inc and tundra-extra.inc are licensed under the 0-Clause BSD
  license
