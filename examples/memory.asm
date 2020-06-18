; Assemble with "nasm -O0 -f bin memory.asm"

cpu 8086

mov cx, 1024
push cx
pop ds
mov di, 55
mov bp, 5

mov [ds:di+bp+404], word 8

mov di, 464
mov ax, [di]