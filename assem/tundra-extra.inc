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
  .read_char? = 0xfff0
  .write_char? = 0xfff1
  .seek_lsw? = 0xfff2
  .seek_msb? = 0xfff3
  .chunk_size? = 0xfff4
  .read_chunk? = 0xfff5
  .write_chunk? = 0xfff6
  .storage_count? = 0xfff7
  .storage_index? = 0xfff8
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
  not dest
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
macro jeq? dest, src1, src2
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src1, *pc
  internal_assert_not_reg src2, *pc

  xor dest, src1
  addi dest, 0x8000    ; smallest signed 16 bit value
  cmpi dest, 0x8000

  jmp src2
end macro

; jump if equal, immediate
macro jeqi? dest, src, imm
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src, *pc

  xor dest, src
  addi dest, 0x8000    ; smallest signed 16 bit value
  cmpi dest, 0x8000

  jmpi imm
end macro

; jump if not equal
macro jne? dest, src1, src2
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src1, *pc
  internal_assert_not_reg src2, *pc

  xor dest, src1
  addi dest, 0x7fff     ; 0 becomes largest signed 16 bit value
  cmpi dest, 0x7ffe     ; don't jump if larger aka if dest == src1

  jmp src2
end macro

; jump if not equal, immediate
macro jneri? dest, src, imm
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src, *pc

  xor dest, src
  addi dest, 0x7fff     ; 0 becomes largest signed 16 bit value
  cmpi dest, 0x7ffe     ; don't jump if larger aka if dest == src1

  jmpi imm
end macro

; jump if not equal, immediate
macro jnei? dest, imm1, imm2
  internal_assert_not_reg dest, pc

  xori dest, imm1
  addi dest, 0x7fff     ; 0 becomes largest signed 16 bit value
  cmpi dest, 0x7ffe     ; don't jump if larger aka if dest == src1

  jmpi imm2
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

; must be called before other stack macros
; reserves C for use as the stack pointer
macro stack_init?
  sp? = c
  movi sp, stack_base
end macro

macro push? src
  internal_assert_not_reg src, *pc

  sto sp, src
  addi sp, -2
end macro

macro pushi? imm
  stoi sp, imm
  addi sp, -2
end macro

macro pop? dest
  ; see popj to pop into pc
  internal_assert_not_reg dest, pc

  addi sp, 2
  mov dest, *sp
end macro

macro popj?
  addi sp, 2
  jmp *sp
end macro

; src is offset into the stack
macro peek? dest, src
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  mov dest, sp
  add dest, src
  mov dest, *dest
end macro

; imm is offset into the stack
macro peeki? dest, imm
  internal_assert_not_reg dest, pc

  if imm = 0
    mov dest, *sp
  else
    mov dest, sp
    addi dest, imm
    mov dest, *dest
  end if

end macro

; src1 is offset into stack, src2 is value to poke
macro poke? src1, src2
  internal_assert_not_reg src1, *pc
  internal_assert_not_reg src2, *pc

  add sp, src1
  sto sp, src2
  sub sp, src1
end macro

; src is offset into stack, imm is value to poke
macro pokei? src, imm
  internal_assert_not_reg src, *pc

  add sp, src
  stoi sp, imm
  sub sp, src
end macro

macro drop? src
  internal_assert_not_reg src, *pc

  add sp, src
end macro

macro dropi? imm
  addi sp, imm
end macro

macro call? src
  internal_assert_not_reg src, *pc

  local ret_addr

  pushi ret_addr
  jmp src
  dropi 2               ; if cmp caused jump to be skipped, drop return address
  ret_addr:
end macro

macro calli? imm
  local ret_addr

  pushi ret_addr
  jmpi imm
  dropi 2               ; if cmp caused jump to be skipped, drop return address
  ret_addr:
end macro

; call if equal, register, immediate
macro ceqri? dest, src, imm
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  xori dest, imm1
  addi dest, 0x8000    ; smallest signed 16 bit value
  cmpi dest, 0x8000
  
  calli imm2
end macro

; call if equal, immediate
macro ceqi? dest, imm1, imm2
  internal_assert_not_reg dest, pc

  xori dest, imm1
  addi dest, 0x8000    ; smallest signed 16 bit value
  cmpi dest, 0x8000
  
  calli imm2
end macro

macro ceqpri? dest, src, imm
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  xor dest, src
  cmpi dest, 0

  calli imm
end macro

macro ceqpi? dest, imm1, imm2
  internal_assert_not_reg dest, pc

  xori dest, imm1
  cmpi dest, 0

  calli imm2
end macro

macro cnei? dest, imm1, imm2
  internal_assert_not_reg dest, pc

  xori dest, imm1
  addi dest, 0x7fff
  cmpi dest, 0x7ffe

  calli imm2
end macro

macro cneri? dest, src, imm
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  xor dest, src
  addi dest, 0x7fff
  cmpi dest, 0x7ffe

  calli imm
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

  if imm = 0
    popj
  else
    local skip, continue

    jmpi continue
    jmpi skip
    continue:

    pop dest
    dropi imm
    jmp dest

    skip:
  end if
end macro
