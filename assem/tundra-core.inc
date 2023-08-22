; flat assembler macros for the Tundra 16-bit fantasy computer
; contains the Tundra instruction set and shorthands for loading immediates

; Permission to use, copy, modify, and/or distribute this software for
; any purpose with or without fee is hereby granted.
; 
; THE SOFTWARE IS PROVIDED “AS IS” AND THE AUTHOR DISCLAIMS ALL
; WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES
; OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE
; FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY
; DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
; AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
; OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

element register
    element a? : register + 0
    element b? : register + 1
    element c? : register + 2
    element pc? : register + 3

macro macro_gen_opcode
    macro ?! name, op
        if `name = "macro_gen_opcode_end"
            purge ?
        else
            macro name? dest, src
                deref = 0

                if dest metadata 1 relativeto register
                    destreg = dest metadata 1 - register
                else
                    err "invalid dest operand"
                end if

                match *a, src
                    if a metadata 1 relativeto register
                        srcreg = a metadata 1 - register
                    else
                        err "invalid src operand"
                    end if
                    deref = 1
                else
                    if src metadata 1 relativeto register
                        srcreg = src metadata 1 - register
                    else
                        err "invalid src operand"
                    end if
                end match
                
                db (op shl 5) + (destreg shl 3) + (deref shl 2) + (srcreg)
            end macro

            macro name#i? dest, src
                deref = 0
                name dest, *pc
                dw src
            end macro
        end if
    end macro
end macro

macro_gen_opcode
    mov, 000b
    add, 001b
    neg, 010b
    sto, 011b
    cmp, 100b
    shf, 101b
    and, 110b
    nor, 111b
macro_gen_opcode_end
