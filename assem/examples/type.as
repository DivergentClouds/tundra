include '../tundra-extra.inc'

CR? = 13
LF? = 10

movi a, mmio.read_char
movi b, mmio.write_char

loop:
  mov c, *a

  cmpi c, 0xffff
  jmpi loop ; loop until character is read

  sto b, c
  jnei c, lf, loop
  stoi b, CR
  jmpi loop
