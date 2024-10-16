include '../tundra-extra.inc'

_start:
  stack_init
  calli main
  halt

; main() void
main:
  pushi data.hello
  calli puts

  reti 0


; puts(str: [*:0]u8) void
puts:
  .loop:
    peeki b, 4

    movb b, *b

    cmpi b, 0
    jmpi .end

    movi a, mmio.write_char
    sto a, b

    ; str is 4 bytes deep in the stack
    movi a, 4
    peek b, a
    addi b, 1
    poke a, b
    jmpi .loop

  .end:
  reti 2

data:
.hello:
  db 'Hello, world!', char.cr, char.lf, 0
