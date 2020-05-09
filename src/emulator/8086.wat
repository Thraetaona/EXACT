;; Module-level documentation (Overview) resides in the 'README.md' file.
;;
;; Assemble with 'wat2wasm ./src/emulator/8086.wat -o ./src/emulator/8086.wasm --enable-bulk-memory'



(module $cpu
  (; 
   ; Memory Section
   ;)
  ;; It is possible to define the memory within webassembly like this "(memory 1 16384 shared)",
  ;; however, we currently define it in the host environment and simply export it to this module.
  ;; Where it's defined has no effect on performance, it is purely done to keep the emulator 'modular',
  ;; in a way that it expects memory, basic IO and other components to be provided externally;
  ;; just as a real, physical 8086 would.



  (; 
   ; Import Section
   ;)
  (import "env" "memory" (memory 16 16384))



  (; 
   ; Export Section
   ;)
  (export "start" (func $start))
  (export "memory" (memory 0))



  (; 
   ; Global Section
   ;)
  (; These are instantiation-time global constants, similar to #define 'regName' 'bitNum' in C, solely for convenience.     ;
   ; They are accessed through $registers.set/get interfaces; to ensure efficient and reliable emulation of decoded registers. ;)
  ;; 16-Bit General Purpose registers (Divided into High / low)
  (global $AX i32 (i32.const 0)) ;; 0; Accumulator (divided into AH / AL)
  (global $CX i32 (i32.const 1)) ;; 1; Count (divided into CH / CL)
  (global $DX i32 (i32.const 2)) ;; 2; Data (divided into DH / DL)
  (global $BX i32 (i32.const 3)) ;; 3; Base (divided into BH / BL)
  ;; 16-Bit Index registers 
  (global $SP i32 (i32.const 4)) ;; 4; Stack pointer 
  (global $BP i32 (i32.const 5)) ;; 5; Base pointer 
  (global $SI i32 (i32.const 6)) ;; 6; Source index
  (global $DI i32 (i32.const 7)) ;; 7; Destination index

  ;; 8-Bit decoded registers
  (global $AL i32 (i32.const 0)) ;; 0; Accumulator low
  (global $CL i32 (i32.const 2)) ;; 1; Count low
  (global $DL i32 (i32.const 4)) ;; 2; Data low
  (global $BL i32 (i32.const 6)) ;; 3; Base low
  (global $AH i32 (i32.const 1)) ;; 4; Accumulator High
  (global $CH i32 (i32.const 3)) ;; 5; Count High
  (global $DH i32 (i32.const 5)) ;; 6; Data High
  (global $BH i32 (i32.const 7)) ;; 7; Base high

  ;; Segment registers 
  (global $ES i32 (i32.const 0)) ;; Extra segment
  (global $CS i32 (i32.const 1)) ;; Code segment
  (global $SS i32 (i32.const 2)) ;; Stack segment
  (global $DS i32 (i32.const 3)) ;; Data segment


  (; The followings are actual global variables.  Unlike the above registers these are accessed directly; as they only represent a single bit. ;)
  ;; Status Flag Registers
  (global $CF (export "CF") (mut i32) (i32.const 0)) ;; bit 0; Carry (Borrow) flag
  (global $PF (export "PF") (mut i32) (i32.const 0)) ;; bit 2; Parity flag
  (global $AF (export "AF") (mut i32) (i32.const 0)) ;; bit 4; Auxiliary (Adjust) flag
  (global $OF (export "OF") (mut i32) (i32.const 0)) ;; bit 11; Overflow flag
  (global $ZF (export "ZF") (mut i32) (i32.const 0)) ;; bit 6; Zero flag
  (global $SF (export "SF") (mut i32) (i32.const 0)) ;; bit 7; Sign flag
  ;; Control Flag Registers
  (global $TF (export "TF") (mut i32) (i32.const 0)) ;; bit 8; Trap flag
  (global $IF (export "IF") (mut i32) (i32.const 0)) ;; bit 9; Interrupt flag
  (global $DF (export "DF") (mut i32) (i32.const 0)) ;; bit 10; Direction flag
  ;; Reserved Flag Registers
  ;; Apparently, the 8086 had some 'reserved' flags that were always(?) set to 1.
  (global $UD_1 i32 (i32.const 1)) ;; bit 1; Unused
  (global $UD_3 i32 (i32.const 1)) ;; bit 3; Unused
  (global $UD_5 i32 (i32.const 1)) ;; bit 5; Unused
  (global $IOPL i32 (i32.const 1)) ;; bits 12 and 13; I/O privilege level in 80286+
  (global $NT i32 (i32.const 1)) ;; bit 14; Called 'Nested Task' in 80286+
  (global $UD_15 i32 (i32.const 1)) ;; bit 15; Unused



  (; 
   ; Table Section
   ;)
  ;; lookup table for dynamic dispatch of opcodes readen from hex code.
  (table $opcodes.fetch 256 256 funcref) (elem (i32.const 0) 
    (;  0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F    / ;)
    $0x00 $0x01 $0x02 $0x03 $0x04 $0x05 $0x06 $0x07 $0x08 $0x09 $0x0a $0x0b $0x0c $0x0d $0x0e $0x0f (; 0 ;)
(;    $0x10 $0x11 $0x12 $0x13 $0x14 $0x15 $0x16 $0x17 $0x18 $0x19 $0x1a $0x1b $0x1c $0x1d $0x1e $0x1f (; 1 ;)
    $0x20 $0x21 $0x22 $0x23 $0x24 $0x25 $0x26 $0x27 $0x28 $0x29 $0x2a $0x2b $0x2c $0x2d $0x2e $0x2f (; 2 ;)
    $0x30 $0x31 $0x32 $0x33 $0x34 $0x35 $0x36 $0x37 $0x38 $0x39 $0x3a $0x3b $0x3c $0x3d $0x3e $0x3f (; 3 ;)
    $0x40 $0x41 $0x42 $0x43 $0x44 $0x45 $0x46 $0x47 $0x48 $0x49 $0x4a $0x4b $0x4c $0x4d $0x4e $0x4f (; 4 ;)
    $0x50 $0x51 $0x52 $0x53 $0x54 $0x55 $0x56 $0x57 $0x58 $0x59 $0x5a $0x5b $0x5c $0x5d $0x5e $0x5f (; 5 ;)
    $0x60 $0x61 $0x62 $0x63 $0x64 $0x65 $0x66 $0x67 $0x68 $0x69 $0x6a $0x6b $0x6c $0x6d $0x6e $0x6f (; 6 ;)
    $0x70 $0x71 $0x72 $0x73 $0x74 $0x75 $0x76 $0x77 $0x78 $0x79 $0x7a $0x7b $0x7c $0x7d $0x7e $0x7f (; 7 ;)
    $UNDF $UNDF $UNDF $UNDF $0x84 $0x85 $0x86 $0x87 $0x88 $0x89 $0x8a $0x8b $0x8c $0x8d $0x8e $0x8f (; 8 ;)
    $0x90 $0x91 $0x92 $0x93 $0x94 $0x95 $0x96 $0x97 $0x98 $0x99 $0x9a $0x9b $0x9c $0x9d $0x9e $0x9f (; 9 ;)
    $0xa0 $0xa1 $0xa2 $0xa3 $0xa4 $0xa5 $0xa6 $0xa7 $0xa8 $0xa9 $0xaa $0xab $0xac $0xad $0xae $0xaf (; A ;)
    $0xb0 $0xb1 $0xb2 $0xb3 $0xb4 $0xb5 $0xb6 $0xb7 $0xb8 $0xb9 $0xba $0xbb $0xbc $0xbd $0xbe $0xbf (; B ;)
    $0xc0 $0xc1 $0xc2 $0xc3 $0xc4 $0xc5 $0xc6 $0xc7 $0xc8 $0xc9 $0xca $0xcb $0xcc $0xcd $0xce $0xcf (; C ;)
    $UNDF $UNDF $UNDF $UNDF $0xd4 $0xd5 $0xd6 $0xd7 $UNDF $UNDF $UNDF $UNDF $UNDF $UNDF $UNDF $UNDF (; D ;)
    $0xe0 $0xe1 $0xe2 $0xe3 $0xe4 $0xe5 $0xe6 $0xe7 $0xe8 $0xe9 $0xea $0xeb $0xec $0xed $0xee $0xef (; E ;)
    $0xf0 $0xf1 $0xf2 $0xf3 $0xf4 $0xf5 $UNDF $UNDF $0xf8 $0xf9 $0xfa $0xfb $0xfc $0xfd $UNDF $UNDF (; F ;) ;)
  )



  (; 
   ; Start Section
   ;)
  (func $start
  
  (call $registers.set16 (global.get $AX) (i32.const 0xf100))

  (call $registers.set16 (global.get $BX) (i32.const 55555))

  (call $registers.set16 (global.get $DI) (i32.const 21))
  (call $registers.set16 (global.get $SI) (i32.const 40404))


  (call $registers.set8 (global.get $CL) (i32.const 255))
  (call $registers.set8 (global.get $CH) (i32.const 255))

  (call $registers.set8 (global.get $DH) (i32.const 2))
  (call $registers.set8 (global.get $DL) (i32.const 1))

  (global.set $CF (i32.const 1))
  (global.set $OF (i32.const 1))
  (global.set $ZF (i32.const 1))

  )



  (; 
   ; Code Section
   ;)
  (; Helper functions ;)
  ;; Stores a 16-Bit value in a general-purpose register.
  (func $registers.set16 (param $bit i32) (param $value i32)
    (i32.store16
      (i32.mul ;; Ensure that the registers are not overlapping.
        (i32.rem_u ;; validation to ensure that the bit is 0 to 7.
          (local.get $bit)
          (i32.const 8)
        )
        (i32.const 2)
      )
      (local.get $value)
    )
  )
  ;; Retrieves a previously stored 16-Bit value value from the specified register.
  (func $registers.get16 (param $bit i32) (result i32)
    (i32.load16_s 
      (i32.mul ;; Ensure that the registers are not overlapping.
        (i32.rem_u ;; validation to ensure that other memory locations are not revealed.
          (local.get $bit)
          (i32.const 8)
        )
        (i32.const 2)
      )
    )
  )
  ;; Stores a 8-Bit value in a general-purpose register.
  (func $registers.set8 (param $bit i32) (param $value i32)
    (i32.store8
      (i32.rem_u ;; validation to ensure that the bit is 0 to 7.
        (local.get $bit)
        (i32.const 8)
      )
      (local.get $value)
    )
  )
  ;; Retrieves a previously stored 8-Bit value value from the specified register.
  (func $registers.get8 (param $bit i32) (result i32)
    (i32.load8_s 
      (i32.rem_u ;; validation to ensure that other memory locations are not revealed.
        (local.get $bit)
        (i32.const 8)
      )
    )
  )

  ;; Sets Zero/Sign/Parity flags accordingly to the resulting value from math operations, 'consuming' the said value in process.
  (func $flags.set_zsp (param $value i32)
    ;; If the value equals 0 then ZF is set to 1; 0 otherwise.
    (select (i32.const 0) (block (result i32) i32.const 0 global.set $SF i32.const 1 global.set $PF i32.const 1 global.set $ZF i32.const 1 br 1)
            (local.get $value)) ;; For 0, we return early; setting other flags appropriately.
    global.set $ZF
    
    ;; If the high-order bit of the value is a 1 then SF is set to 1; 0 otherwise. (Two's complement notation)
    (i32.shr_u (local.get $value) (i32.const 15))
    global.set $SF

    ;; If the value has even parity (an even number of 1-Bits) PF is set to 1, 0 otherwise.
    (i32.xor
      (i32.rem_u
        (i32.popcnt (local.get $value))
        (i32.const 2)
      )
      (i32.const -1)
    )
    global.set $PF
  )
  
  ;; Sets Auxiliary/Overflow/Carry flags just like above.
  (func $flags.set_aoc (param $value i32)
    ;; if the result of a signed operation is too large to be represented in 8-Bits, Then OF is set to 1, 0 otherwise.
      
    
    ;;global.set $OF
  )


  (; Opcode backends ;)
  ;; adds a value (+ an optional carry flag) to a register or memory.
  (func $ADD (param $destination i32) (param $source i32) (result i32)
    local.get $destination
    local.get $source
    i32.add
    global.get $CF
    i32.add
    ;; TODO: push the above value to stack again and use set_aoc.
    ;;call $set_zsp
    ;;return
    ;; It's not possible to pass global variables as function arguments,
    ;; so this function simply returns the resulting number and sets arithmeticaal flags accordingly.  
    ;; setting destination to the said value is done in opcodes.
  )


  (; Opcodes ;)
  (func $0x00 (; ADD ;) (;
    i32.const 0
    call $ADD
    global.set $ ;)
  )
  (func $0x01 (; ADD ;) (;
    i32.const 0
    call $ADD
    global.set $ ;)
  )
  (func $0x02 (; ADD ;) (;
    i32.const 0
    call $ADD
    global.set $ ;)
  )
  (func $0x03 (; ADD ;) (;
    i32.const 0
    call $ADD
    global.set $ ;)
  )
  (func $0x04 (; ADD AL, Ib;) (;
    i32.const 0
    call $ADD
    global.set $AL ;)
  )
  (func $0x05 (; ADD AX, Iv ;) (;
    i32.const 0
    call $ADD
    global.set $AX ;)
  )
  
  (func $0x06 (; PUSH ES ;)
    ;; work-in-progress
  )
  (func $0x07 (; POP ES ;)
    ;; work-in-progress
  )

  (func $0x08 (; OR ;)
    ;; work-in-progress
  )
  (func $0x09 (; OR ;)
    ;; work-in-progress
  )
  (func $0x0a (; OR ;)
    ;; work-in-progress
  )
  (func $0x0b (; OR ;)
    ;; work-in-progress
  )
  (func $0x0c (; OR ;)
    ;; work-in-progress
  )
  (func $0x0d (; OR ;)
    ;; work-in-progress
  )

  (func $0x0e (; PUSH CS ;)
    ;; work-in-progress
  )

  (func $0x90 (; NOP ;)
    nop
  )


  (; Undocumented or duplicate opcodes ;)
  ;; Most illegal opcodes would just map to other documented instructions (e.g. 0x60 - 0x6f ==> 0x70 – 0x7f);
  ;; while a few others such as 'SALC' actually did something useful.
  ;;
  ;; However, a real 8086 (or anything earlier than 80186) would do nothing when encountering a truly invalid opcode (hence the nop).
  ;; This emulator aims to be FULLY compatible only (i.e. no co-processors) with the original 8086, so it supports the 
  ;; redundant opcodes or others like 'SALC'.  Also, several opcodes (e.g. 0xd8 - 0xdf) are only valid when a co-processor like x87 is present; 
  ;; but since we are emulating this on fast, modern hardware, and co-processors were very rare and expensive back then; 
  ;; emulating a 8087 is out of this project's scope, and therefore invalid.
  (func $UNDF (; illegal instruction ;)
    nop
  )

  (func $0x0f (; POP CS ;)
    ;; work-in-progress
  )

  ;; this opcode sets AL to 256 if the carry flag is set, 0 otherwise.
  (func $0xd6 (; SALC ;)
    (call $registers.set8 
      (global.get $DL)
      (select (i32.const 0xFF) (i32.const 0x00)
              (global.get $CF))
    )
  )


)
