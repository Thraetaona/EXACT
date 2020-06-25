 ; Assemble with "nasm -O0 -f bin checked_add.asm"

cpu 8086


mov ax, 5
mov bx, -5

jmp somewhere

    back:  
    jmp stop

somewhere:
add ax, bx  ; this should set the Zero Flag to 1.
jz back

stop:
mov cx, 404 ; Indicates that  the operation was successful
hlt