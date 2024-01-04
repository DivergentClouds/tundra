include '../tundra-extra.inc'

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
	peeki b, 2

	mov b, *b
	andi b, 0xff

	movi a, 0
	cmp b, a
	jmpi .end

	movi a, mmio.write_char
	sto a, b

	movi a, 2
	peek b, a
	addi b, 1
	poke a, b
	jmpi .loop

	.end:
	reti b, 1

data:
.hello:
	db 'Hello, world!', 10, 0
