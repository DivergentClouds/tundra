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
  .access_address? = 0xfff2
  .block_index? = 0xfff3
  .write_storage? = 0xfff4
  .read_storage? = 0xfff5
  .storage_count? = 0xfff6
  .storage_index? = 0xfff7
  .zero_storage? = 0xfff8
  .boundary_address? = 0xfff9
  .interrupt_address? = 0xfffa
  .previous_interrupt? = 0xfffb
  .halt? = 0xffff
end virtual


char?:
  .lf? = 0x0a           ; IN/OUT
  .bs? = 0x08           ; IN/OUT
  .up? = 0xe9           ; IN/OUT
  .down? = 0xeb         ; IN/OUT
  .left? = 0xea         ; IN/OUT
  .right? = 0xec        ; IN/OUT

  .tab? = 0x09          ; IN
  .insert? = 0xee       ; IN
  .delete? = 0xf8       ; IN
  .home? = 0xe8         ; IN
  .end? = 0xe5          ; IN

  .cr? = 0x0d           ; OUT
  .clear_right? = 0xd2  ; OUT
  .clear_down? = 0xc2   ; OUT
  .clear_all? = 0xd8    ; OUT
  .to_origin? = 0xc8    ; OUT

stack_base? = 0xFFEF

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

macro rotri dest, imm
  internal_assert_not_reg dest, pc

  assert imm >= 0 & imm < 0x8000

  rot dest, imm
end macro

macro rotli dest, imm
  internal_assert_not_reg dest, pc

  assert imm >= 0 & imm < 0x8000

  rot dest, 0 - imm
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

macro movb? dest, src
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src, *pc

  mov dest, src
  andi dest, 0xff
end macro

; jump
macro jmp? src
  internal_assert_not_reg src, *pc

   mov pc, src
end macro

; jump immediate
macro jmpi? imm
  ; subtract 2 because pc is incremented by 2 when the immediate is read
  addi pc, imm - $ - 2
end macro

; clear cmp flag, making jumps until the next `cmp` unconditional
macro clear_flag
  jmp pc ; clears cmp flag, pc is incremented post-fetch, pre-execution
end macro

; jump to src2 if dest equals src1
macro jeq? dest, src1, src2
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src1, *pc
  internal_assert_not_reg src2, *pc

  xor dest, src1
  addi dest, 0x8000    ; smallest signed 16 bit value
  cmpi dest, 0x8000

  jmp src2
end macro

; jump to imm if dest equals src
macro jeqri? dest, src, imm
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src, *pc

  xor dest, src
  addi dest, 0x8000    ; smallest signed 16 bit value
  cmpi dest, 0x8000

  jmpi imm
end macro

; jump to src if dest equals imm
macro jeqir? dest, imm, src
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src, *pc

  if imm <> 0
    xori dest, imm
  end if

  addi dest, 0x8000    ; smallest signed 16 bit value
  cmpi dest, 0x8000

  jmp src
end macro

; jump to imm2 if dest equals imm1
macro jeqi? dest, imm1, imm2
  internal_assert_not_reg dest, pc

  if imm1 <> 0
    xori dest, imm1
  end if

  addi dest, 0x8000    ; smallest signed 16 bit value
  cmpi dest, 0x8000

  jmpi imm2
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

; jump to src2 if equal; assert non-negative
macro jeqp? dest, src1, src2
  internal_assert_not_reg src1, *pc
  internal_assert_not_reg src2, *pc
  internal_assert_not_reg dest, pc

  xor dest, src1
  cmpi dest, 0
  jmp src2
end macro

; jump to imm if equal; assert non-negative
macro jeqpri? dest, src, imm
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  xor dest, src
  cmpi dest, 0
  jmpi imm
end macro

macro jeqpir? dest, imm, src
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  if imm <> 0
    xori dest, imm
  end if

  cmpi dest, 0
  jmp src
end macro

; jump to imm2 if dest and imm1 equal; assert non-negative
macro jeqpi? dest, imm1, imm2
  internal_assert_not_reg dest, pc

  if imm1 <> 0
    xori dest, imm1
  end if

  cmpi dest, 0
  jmpi imm2
end macro

; jump to src2 if dest <= src1 (unsigned)
macro jlequ? dest, src1, src2
  internal_assert_not_reg src1, *pc
  internal_assert_not_reg src2, *pc
  internal_assert_not_reg dest, pc

  local skip1, skip2, skip3

  ; NOTE: `a <=u b` should be `a <=s b and (a >=s 0 or b <s 0)`

  ; a <=s b?
  cmp dest, src1
  jmpi skip1
  jmpi skip3

  ; a >=s 0?
  skip1:
  cmpi dest, -1
  jmpi skip2
  jmp src2

  ; b <s 0?
  skip2:
  mov dest, src1
  cmpi dest, -1
  jmp src2

  skip3:
end macro

; jump to imm if dest <= src (unsigned)
macro jlequri? dest, src, imm
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  local skip1, skip2, skip3

  ; NOTE: `a <=u b` should be `a <=s b and (a >=s 0 or b <s 0)`

  ; a <=s b?
  cmp dest, src
  jmpi skip1
  jmpi skip3

  ; a >=s 0?
  skip1:
  cmpi dest, -1
  jmpi skip2
  jmpi imm

  ; b <s 0?
  skip2:
  mov dest, src
  cmpi dest, -1
  jmpi imm

  skip3:
end macro

; jump to imm2 if dest <= imm1 (unsigned)
macro jlequi? dest, imm1, imm2
  internal_assert_not_reg dest, pc

  local skip1, skip2, skip3

  ; NOTE: `a <=u b` should be `a <=s b and (a >=s 0 or b <s 0)`

  ; a <=s b?
  cmpi dest, imm1
  jmpi skip1
  jmpi skip3

  ; a >=s 0?
  skip1:
  cmpi dest, -1

  ; b <s 0?
  if imm1 < 0 | imm1 >= 0x7fff
    clear_flag
  end if

  jmpi imm2

  skip3:
end macro

; jump to src2 if dest > src1 (unsigned)
macro jgtu? dest, src1, src2
  internal_assert_not_reg src1, *pc
  internal_assert_not_reg src2, *pc
  internal_assert_not_reg dest, pc

  local skip1, skip2, skip3

  ; NOTE: `a >u b` should be `a >s b or (a <s 0 and b >=s 0)`

  ; a >s b?
  cmp dest, src1
  jmpi skip1
  jmp src2

  ; a <s 0?
  skip1:
  cmpi dest, -1
  jmpi skip2
  jmpi skip3

  ; b >=s 0?
  skip2:
  mov dest, src1
  cmpi dest, -1
  jmpi skip3
  jmp src2

  skip3:
end macro

; jump to imm if dest > src (unsigned)
macro jgturi? dest, src, imm
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  local skip1, skip2, skip3

  ; NOTE: `a >u b` should be `a >s b or (a <s 0 and b >=s 0)`

  ; a >s b?
  cmp dest, src
  jmpi skip1
  jmpi imm

  ; a <s 0?
  skip1:
  cmpi dest, -1
  jmpi skip2
  jmpi skip3

  ; b >=s 0?
  skip2:
  mov dest, src
  cmpi dest, -1
  jmpi skip3
  jmpi imm

  skip3:
end macro

; jump to imm2 if dest > imm1 (unsigned)
macro jgtui? dest, imm1, imm2
  internal_assert_not_reg dest, pc

  local skip1

  ; NOTE: `a >u b` should be `a >s b or (a <s 0 and b >=s 0)`

  ; a >s b?
  cmpi dest, imm1
  jmpi skip1
  jmpi imm2

  ; b >=s 0?
  skip1:
  if imm1 >= 0
    ; a <s 0?
    cmpi dest, -1
    jmpi imm2
  end if
end macro

; jump to src if dest == 0
macro jeqz? dest, src
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src, *pc

  addi dest, 0x8000    ; smallest signed 16 bit value
  cmpi dest, 0x8000

  jmp src2
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
  subi sp, 2
end macro

macro pushi? imm
  stoi sp, imm
  subi sp, 2
end macro

; asserts that src is in the range 0x00 through 0xff
macro pushb? src
  internal_assert_not_reg src, *pc

  sto sp, src
  subi sp, 1
end macro

; asserts that src is in the range 0x00 through 0xff
macro pushbi? imm
  assert imm > 0 & imm <= 0xff

  stoi sp, imm
  subi sp, 1
end macro

; see popj to pop into pc
macro pop? dest
  internal_assert_not_reg dest, pc

  addi sp, 2
  mov dest, *sp
end macro

macro popb? dest
  internal_assert_not_reg dest, pc

  addi sp, 1
  mov dest, *sp
  andi dest, 0xff
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

; poke, immediate, immediate
; imm1 is offset into stack, imm2 is value to poke
macro pokei? imm1, imm2
  if imm1 = 0
    stoi sp, imm2
  else
    addi sp, imm1
    stoi sp, imm2
    subi sp, imm1
  end if
end macro

; poke, immediate, register
; imm is offset into stack, src is value to poke
macro pokeir? imm, src
  internal_assert_not_reg src, *pc

  if imm = 0
    sto sp, src
  else
    addi sp, imm
    sto sp, src
    subi sp, imm
  end if
end macro

; poke, register, immediate
; src is offset into stack, imm is value to poke
macro pokeri? src, imm
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
