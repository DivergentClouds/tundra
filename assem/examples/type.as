include '../tundra-extra.inc'

movi a, mmio.read_char
movi b, mmio.write_char

loop:
  mov c, *a

  cmpi c, -1
  jmpi loop ; loop until character is read

  sto b, c
  jnei c, char.cr, loop
  stoi b, char.lf
  jmpi loop
