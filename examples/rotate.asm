; Assemble with "nasm -O0 -f bin rotate.asm"

cpu 8086


stc
mov cl, 00011100b
rcl cl, 1   ; CL = 00111001b, CF = 0

mov al, 250
rol al, 1   ; CL = 500, OF = 0