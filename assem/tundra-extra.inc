; various extra fasmg macros for Tundra

; Permission to use, copy, modify, and/or distribute this software for
; any purpose with or without fee is hereby granted.

; THE SOFTWARE IS PROVIDED “AS IS” AND THE AUTHOR DISCLAIMS ALL
; WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES
; OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE
; FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY
; DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
; AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
; OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

include 'tundra-core.inc'

virtual at 0xfff0
	mmio?:
	.input_available? = 0xfff0
	.read_char? = 0xfff1
	.write_char? = 0xfff2
	.seek_lsw? = 0xfff3
	.seek_msb? = 0xfff4
	.chunk_size? = 0xfff5
	.read_chunk? = 0xfff6
	.write_chunk? = 0xfff7
	.storage_count? = 0xfff8
	.storage_index? = 0xfff9
	.halt? = 0xffff
end virtual

stack_base? = 0xFFEE

; for internal use, makes sure a valid register is given
macro internal_assert_not_reg? reg1, reg2
	assert `reg1 <> `reg2
end macro

macro halt?
	movi a, mmio.halt
	sto a, a
end macro

macro not? dest
  internal_assert_not_reg dest, pc

  nor dest, dest
end macro

macro or? dest, src
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  nor dest, src
  not dest
end macro

macro ori? dest, imm
  internal_assert_not_reg dest, pc

  nori dest, imm
  neg dest
end macro

macro shri? dest, imm
  internal_assert_not_reg dest, pc
  assert imm < 16
  assert imm >= 0
 
  shfi dest, imm or 0b10000
end macro

macro shli? dest, imm
  internal_assert_not_reg dest, pc
  assert imm < 16
  assert imm >= 0
 
  shfi dest, imm
end macro

macro asri? dest, imm
  internal_assert_not_reg dest, pc
  assert imm < 16
  assert imm >= 0
  
  shfi dest, imm or 0b1000000
end macro

macro rtli? dest, imm
  internal_assert_not_reg dest, pc
  assert imm < 16
  assert imm >= 0
  
  shfi dest, imm or 0b110000
end macro

macro rtri? dest, imm
  internal_assert_not_reg dest, pc
  assert imm < 16
  assert imm >= 0
  
  shfi dest, imm or 0b100000
end macro

macro neg? dest
  internal_assert_not_reg dest, pc

  not dest
  addi dest, 1
end macro

macro sub? dest, src
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  neg dest
  add dest, src
  neg dest
end macro

macro subi? dest, imm
  internal_assert_not_reg dest, pc

  addi dest, 0 - imm
end macro

; jump
macro jmp? src
  internal_assert_not_reg src, *pc

 	mov pc, src
end macro

; jump immediate
macro jmpi? imm
 	movi pc, imm
end macro

; jump if equal
macro jeq? dest1, dest2, src
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest1, pc
  internal_assert_not_reg dest2, pc

 	local next, skip

	cmp dest1, dest2
	jmpi next ; dest1 <= dest2

	jmpi skip ; dest1 > dest2

	next:
	cmp dest2, dest1
	jmp src ; dest2 <= dest1 -> dest1 == dest2

	skip:
end macro

; jump if equal immediate
macro jeqi? dest1, dest2, imm
  internal_assert_not_reg dest1, pc
  internal_assert_not_reg dest2, pc

 	local next, skip

	cmp dest1, dest2
	jmpi next ; dest1 <= dest2

	jmpi skip ; dest1 > dest2

	next:
	cmp dest2, dest1
	jmpi imm; dest2 <= dest1 -> dest1 == dest2

	skip:
end macro

; jump if not equal
macro jne? dest1, dest2, src
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

 	local skip

	jeqi dest1, dest2, skip
	jmp src
	skip:
end macro

; jump if not equal immediate
macro jnei? dest1, dest2, imm
  internal_assert_not_reg dest1, pc
  internal_assert_not_reg dest2, pc
 	local skip

	jeqi dest1, dest2, skip
	jmpi imm
	skip:
end macro

; jump to src2 if equal; assert positive
macro jeqp? dest, src1, src2
  internal_assert_not_reg src1, *pc
  internal_assert_not_reg src2, *pc
  internal_assert_not_reg dest, pc

 	xor dest, src1
	cmpi dest, 0
	jmp src2
end macro

; jump to imm if equal; assert positive
macro jeqpri? dest, src, imm
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

 	xor dest, src
	cmpi dest, 0
	jmpi imm
end macro

; jump to imm2 if dest and imm1 equal; assert positive
macro jeqpi? dest, imm1, imm2
  internal_assert_not_reg dest, pc

 	xori dest, imm1
	cmpi dest, 0
	jmpi imm2
end macro

; jump to src2 if not equal; assert positive
macro jnep? dest, src1, src2
  internal_assert_not_reg src1, *pc
  internal_assert_not_reg src2, *pc
  internal_assert_not_reg dest, pc

 	local skip

	xori dest, src1
	cmpi dest, 0
	jmpi skip
	jmp src2

	skip:
end macro

; jump to imm if not equal; assert positive
macro jnepri? dest, src, imm
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

 	local skip

	xor dest, src
	cmpi dest, 0
	jmpi skip
	jmpi imm

	skip:
end macro

; jump to imm2 if dest and imm1 not equal; assert positive
macro jnepi? dest, imm1, imm2
  internal_assert_not_reg dest, pc

 	local skip

	xori dest, imm1
	cmpi dest, 0
	jmpi skip
	jmpi imm2

	skip:
end macro

; must be called before other stack macros
; reserves C for use as the stack pointer
macro stack_init?
	movi c, stack_base
end macro

macro push? src
  internal_assert_not_reg src, *pc

 	sto c, src
	addi c, -2
end macro

macro pushi? imm
	stoi c, imm
	addi c, -2
end macro

macro pop? dest
  ; see popj to pop into pc
  internal_assert_not_reg dest, pc

	addi c, 2
	mov dest, *c
end macro

macro popj?
  addi c, 2
  jmp *c
end macro

; src is offset into the stack
macro peek? dest, src
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

	mov dest, c
	add dest, src
	mov dest, *dest
end macro

; imm is offset into the stack
macro peeki? dest, imm
  internal_assert_not_reg dest, pc

	mov dest, c
	addi dest, imm
	mov dest, *dest
end macro

; dest is offset into stack, src is value to poke
macro poke? dest, src
  internal_assert_not_reg src, *pc

	add c, dest
	sto c, src
  sub c, dest
end macro

; dest is offset into stack, imm is value to poke
macro pokei? dest, imm
	add c, dest
	stoi c, imm
  sub c, dest
end macro

macro drop? src
  internal_assert_not_reg src, *pc

  add c, src
end macro

macro dropi? imm
	addi c, imm
end macro

macro call? src
  internal_assert_not_reg src, *pc

	local ret_addr

	pushi ret_addr
	jmp src
	dropi 2			; if cmp caused jump to be skipped, drop return address
	ret_addr:
end macro

macro calli? imm
	local ret_addr

	pushi ret_addr
	jmpi imm
	dropi 2		; if cmp caused jump to be skipped, drop return address
	ret_addr:
end macro

macro ret? dest, src
  internal_assert_not_reg src, *pc
	internal_assert_not_reg dest, pc

	local skip, continue

	jmpi continue
	jmpi skip
	continue:

	pop dest
	drop src
	jmp dest

	skip:
end macro

macro reti? dest, imm
	internal_assert_not_reg dest, pc

	local skip, continue

	jmpi continue
	jmpi skip
	continue:

	pop dest
	dropi imm
	jmp dest

	skip:
end macro
