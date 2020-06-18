; Assemble with "nasm -O0 -f bin stack.asm"

cpu 8086


mov ax, 100h
mov ss, ax
mov sp, 100h

mov bx, 500
push bx

mov bp, sp

mov dx, [bp]
