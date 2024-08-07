include '../tundra-extra.inc'

CR? = 13
LF? = 10

_start:
  stack_init
  calli main
  halt

; main() void
main:
  pushi data.hello
  calli puts

  reti b, 0


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
  reti b, 2

data:
.hello:
  db 'Hello, world!', LF, CR, 0
