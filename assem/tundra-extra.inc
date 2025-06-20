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

if ~ definite internal_tundra_extra_guard
internal_tundra_extra_guard := 1

include 'tundra-core.inc'

virtual at 0xfff0
  mmio?:
  .char_in? = 0xfff0
  .char_out? = 0xfff0
  .char_io? = 0xfff0
  .get_cursor? = 0xfff1
  .set_cursor? = 0xfff1
  .cursor? = 0xfff1
  .seek_storage? = 0xfff2
  .storage_ready? = 0xfff3
  .store_block? = 0xfff3
  .load_block? = 0xfff4
  .storage_count? = 0xfff5
  .storage_index? = 0xfff5
  .storage_device? = 0xfff5
  .int_handler? = 0xfff6
  .int_from? = 0xfff7
  .int_kind? = 0xfff8
  .enabled_ints? = 0xfff9
  .bank_map? = 0xfffa
  .time? = 0xfffb
  .date? = 0xfffc
  .halt? = 0xffff
end virtual

int?:
  .read_protect? = 0x01
  .write_protect? = 0x02
  .exec_protect? = 0x04
  .timer? = 0x08
  .keyboard? = 0x10

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

; top of region 3, so is not caught by memory protection
stack_base? = 0xbffe

; for internal use, makes sure a valid register is given
macro internal_assert_not_reg? reg1, reg2
  assert `reg1 <> `reg2
end macro

macro internal_construct_bits? name, count
  name = 0

  repeat count
    name = name shl 1
    name = name or 1
  end repeat 
end macro

; switch dest to refer to a primary register
macro to_prime? dest
  internal_assert_not_reg dest, pc

  mov dest, dest
end macro

; switch dest to refer to a secondary register
macro to_alt? dest
  internal_assert_not_reg dest, pc

  and dest, dest
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

macro rotli dest, imm
  internal_assert_not_reg dest, pc

  assert imm > 0 & imm < 16

  roti dest, imm
end macro

macro rotri dest, imm
  internal_assert_not_reg dest, pc

  assert imm > 0 & imm < 16

  roti dest, 0 - imm
end macro

macro shri dest, imm
  internal_assert_not_reg dest, pc

  assert imm > 0 & imm < 16

  local mask
  internal_construct_bits mask, imm
  mask = mask shl 16 - imm
  mask = not mask

  rotri dest, imm
  andi dest, mask
end macro

macro shli dest, imm
  internal_assert_not_reg dest, pc

  assert imm > 0 & imm < 16

  local mask
  internal_construct_bits mask, imm
  mask = not mask

  rotli dest, imm
  andi dest, mask
end macro

macro neg? dest
  internal_assert_not_reg dest, pc

  not dest
  addi dest, 1
end macro

macro sub? dest, src
  internal_assert_not_reg src, *pc
  internal_assert_not_reg dest, pc

  not dest
  add dest, src
  not dest
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

; mov an address into dest, relative to the current position
; for relocatable code
macro movreli? dest, imm
  internal_assert_not_reg dest, pc

  ; mmio addresses are never relocated
  assert imm >= 0 & imm < mmio
  
  ; not equivalent to $ in case of code relocation
  mov dest, pc

  ; add 2 because 2 instructions in macro
  addi dest, imm - $ + 2
end macro

; jump
macro jmp? src
  internal_assert_not_reg src, *pc

  mov pc, src
end macro

; jump immediate, relative to the current position
macro jmpi? imm
  ; subtract 2 because pc is incremented by 2 when the immediate is read
  addi pc, imm - $ - 2
end macro

; jump immediate, absolute location
macro jabsi? imm
  movi pc, imm
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

  if imm1 <> 0
    xori dest, imm1
  end if

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

; jump to src if dest <= imm (unsigned)
macro jlequir? dest, imm, src
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src, *pc

  local skip1, skip2, skip3

  ; NOTE: `a <=u b` should be `a <=s b and (a >=s 0 or b <s 0)`

  ; a <=s b?
  cmpi dest, imm
  jmpi skip1
  jmpi skip3

  ; a >=s 0?
  skip1:
  cmpi dest, -1
  jmpi skip2
  jmp src

  skip2:
  ; b <s 0?
  if imm1 < 0 | imm1 > 0x7fff
    jmp src
  end if

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
  jmpi skip2
  jmpi imm2

  skip2:
  ; b <s 0?
  if imm1 < 0 | imm1 > 0x7fff
    jmpi imm2
  end if

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

; jump to src if dest > imm (unsigned)
macro jgtuir? dest, imm, src
  internal_assert_not_reg dest, pc
  internal_assert_not_reg src, *pc

  local skip1

  ; NOTE: `a >u b` should be `a >s b or (a <s 0 and b >=s 0)`

  ; a >s b?
  cmpi dest, imm
  jmpi skip1
  jmp src

  ; b >=s 0?
  skip1:
  if imm >= 0
    ; a <s 0?
    cmpi dest, -1
    jmp src
  end if
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
  
  assert imm <> 0

  mov dest, sp
  addi dest, imm
  mov dest, *dest
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
  assert imm1 <> 0

  addi sp, imm1
  stoi sp, imm2
  subi sp, imm1
end macro

; poke, immediate, register
; imm is offset into stack, src is value to poke
macro pokeir? imm, src
  internal_assert_not_reg src, *pc

  assert imm <> 0

  addi sp, imm
  sto sp, src
  subi sp, imm
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
end macro

macro calli? imm
  local ret_addr

  pushi ret_addr
  jabsi imm
  ret_addr:
end macro

; calli, but for relocatable code
; overwrites b register
macro creli? imm
  local ret_addr

  movreli b, ret_addr
  push b
  jmpi imm
  ret_addr:
end macro

; return from current function, dropping src bytes of arguments from the stack
; overwrites b register
macro ret? src
  internal_assert_not_reg src, *pc
  internal_assert_not_reg src b
  internal_assert_not_reg src *b

  pop b
  drop src
  jmp b
end macro

; return from current function, dropping imm bytes of arguments from the stack
; overwrites b register
macro reti? imm
  if imm = 0
    popj
  else
    pop b
    dropi imm
    jmp b
  end if
end macro

end if
