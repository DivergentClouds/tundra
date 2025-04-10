include '../tundra-extra.inc'

movi a, mmio.char_io


loop:
  mov b, *a

  cmpi b, -1
  jmpi loop ; loop until character is read

  sto a, b
  jeqpi b, char.cr, exit
  jmpi loop

exit:
  stoi a, char.lf
  movi a, mmio.halt
  sto a, a
