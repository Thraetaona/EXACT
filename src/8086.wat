;; Module-level documentation (Overview) resides in the 'README.md' file.


(module $cpu
  (; Memory Section ;)
  ;; It is possible to define memory within webassembly like this "(memory 1 16384 shared)",
  ;; however, we currently define it in the host environment and simply export it to this module.
  ;; Where it's defined has no effect on performance, it is purely done to keep the emulator 'modular'
  ;; in a way that it expects memory, basic IO and other components to be provided externally;
  ;; just as a real, physical 8086 would.


  (; Import Section ;)
  (import "env" "memory" (memory 16 16384 shared))


  (; Export Section ;)
  (export "start" (func $start))


  (; Global Section ;)
  ;; 16-bit register decodes
  ;; General Purpose Registers
  (global $AX (mut i32) (i32.const 0))
  (global $CX (mut i32) (i32.const 1))
  (global $DX (mut i32) (i32.const 2))
  (global $BX (mut i32) (i32.const 3))

  ;; Index Registers 
  (global $SP (mut i32) (i32.const 4))
  (global $BP (mut i32) (i32.const 5))
  (global $SI (mut i32) (i32.const 6))
  (global $DI (mut i32) (i32.const 7))

  ;; Segment Registers 
  (global $ES (mut i32) (i32.const 8))
  (global $CS (mut i32) (i32.const 9))
  (global $SS (mut i32) (i32.const 10))
  (global $DS (mut i32) (i32.const 11))

  (global $ZERO i32 (i32.const 12))
  (global $SCRATCH i32 (i32.const 13))

  ;; 8-bit register decodes
  (global $AL (mut i32) (i32.const 0))
  (global $AH (mut i32) (i32.const 1))
  (global $CL (mut i32) (i32.const 2))
  (global $CH (mut i32) (i32.const 3))
  (global $DL (mut i32) (i32.const 4))
  (global $DH (mut i32) (i32.const 5))
  (global $BL (mut i32) (i32.const 6))
  (global $BH (mut i32) (i32.const 7))

  ;; Flag Registers
  (global $CF (mut i32) (i32.const 40))
  (global $PF (mut i32) (i32.const 41))
  (global $AF (mut i32) (i32.const 42))
  (global $ZF (mut i32) (i32.const 43))
  (global $SF (mut i32) (i32.const 44))
  (global $TF (mut i32) (i32.const 45))
  (global $IF (mut i32) (i32.const 46))
  (global $DF (mut i32) (i32.const 47))
  (global $OF (mut i32) (i32.const 48))

  ;; Lookup tables in the BIOS binary
  (global $XLAT_OPCODE i32 (i32.const 8))
  (global $XLAT_SUBFUNCTION i32 (i32.const 9))
  (global $STD_FLAGS i32 (i32.const 10))
  (global $PARITY_FLAG i32 (i32.const 11))
  (global $BASE_INST_SIZE i32 (i32.const 12))
  (global $I_W_SIZE i32 (i32.const 13))
  (global $I_MOD_SIZE i32 (i32.const 14))
  (global $COND_JUMP_DECODE_A i32 (i32.const 15))
  (global $COND_JUMP_DECODE_B i32 (i32.const 16))
  (global $COND_JUMP_DECODE_C i32 (i32.const 17))
  (global $COND_JUMP_DECODE_D i32 (i32.const 18))
  (global $BITFIELDS i32 (i32.const 19))

  ;; Bitfields for TABLE_STD_FLAGS values
  (global $UPDATE_SZP i32 (i32.const 1))
  (global $UPDATE_AO_ARITH i32 (i32.const 2))
  (global $UPDATE_OC_LOGIC i32 (i32.const 4))


  (; Table Section ;)
  (table $opcodes 256 256 funcref) (elem (i32.const 0) 
    (;  0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F    / ;)
    $0x00 $0x01 $0x02 $0x03 $0x04 $0x05 $0x06 $0x07 $0x08 $0x09 $0x0a $0x0b $0x0c $0x0d $0x0e $0x0f (; 0 ;)
    $0x10 $0x11 $0x12 $0x13 $0x14 $0x15 $0x16 $0x17 $0x18 $0x19 $0x1a $0x1b $0x1c $0x1d $0x1e $0x1f (; 1 ;)
    $0x20 $0x21 $0x22 $0x23 $0x24 $0x25 $0x26 $0x27 $0x28 $0x29 $0x2a $0x2b $0x2c $0x2d $0x2e $0x2f (; 2 ;)
    $0x30 $0x31 $0x32 $0x33 $0x34 $0x35 $0x36 $0x37 $0x38 $0x39 $0x3a $0x3b $0x3c $0x3d $0x3e $0x3f (; 3 ;)
    $0x40 $0x41 $0x42 $0x43 $0x44 $0x45 $0x46 $0x47 $0x48 $0x49 $0x4a $0x4b $0x4c $0x4d $0x4e $0x4f (; 4 ;)
    $0x50 $0x51 $0x52 $0x53 $0x54 $0x55 $0x56 $0x57 $0x58 $0x59 $0x5a $0x5b $0x5c $0x5d $0x5e $0x5f (; 5 ;)
    $0x60 $0x61 $0x62 $0x63 $0x64 $0x65 $0x66 $0x67 $0x68 $0x69 $0x6a $0x6b $0x6c $0x6d $0x6e $0x6f (; 6 ;)
    $0x70 $0x71 $0x72 $0x73 $0x74 $0x75 $0x76 $0x77 $0x78 $0x79 $0x7a $0x7b $0x7c $0x7d $0x7e $0x7f (; 7 ;)
    $0x80 $0x81 $0x82 $0x83 $0x84 $0x85 $0x86 $0x87 $0x88 $0x89 $0x8a $0x8b $0x8c $0x8d $0x8e $0x8f (; 8 ;)
    $0x90 $0x91 $0x92 $0x93 $0x94 $0x95 $0x96 $0x97 $0x98 $0x99 $0x9a $0x9b $0x9c $0x9d $0x9e $0x9f (; 9 ;)
    $0xa0 $0xa1 $0xa2 $0xa3 $0xa4 $0xa5 $0xa6 $0xa7 $0xa8 $0xa9 $0xaa $0xab $0xac $0xad $0xae $0xaf (; A ;)
    $0xb0 $0xb1 $0xb2 $0xb3 $0xb4 $0xb5 $0xb6 $0xb7 $0xb8 $0xb9 $0xba $0xbb $0xbc $0xbd $0xbe $0xbf (; B ;)
    $0xc0 $0xc1 $0xc2 $0xc3 $0xc4 $0xc5 $0xc6 $0xc7 $0xc8 $0xc9 $0xca $0xcb $0xcc $0xcd $0xce $0xcf (; C ;)
    $0xd0 $0xd1 $0xd2 $0xd3 $0xd4 $0xd5 $0xd6 $0xd7 $UD   $UD   $UD   $UD   $UD   $UD   $UD   $UD   (; D ;)
    $0xe0 $0xe1 $0xe2 $0xe3 $0xe4 $0xe5 $0xe6 $0xe7 $0xe8 $0xe9 $0xea $0xeb $0xec $0xed $0xee $0xef (; E ;)
    $0xf0 $0xf1 $0xf2 $0xf3 $0xf4 $0xf5 $0xf6 $0xf7 $0xf8 $0xf9 $0xfa $0xfb $0xfc $0xfd $0xfe $0xff (; F ;)
  )


  (; Start Section ;)
  (func $start
  
    block
      nop
      (i32.add (i32.const 1) (i32.const 2))
      drop
    end

  )
  

  (; Code Section ;)

  (; Opcodes ;)
  (func $0x00 (; ADD ;)
    ;; work-in-progress
  )

  (func $0x90 (; NOP ;)
    nop
  )

  (; Undocumented or duplicate opcodes ;)
  ;; Most illegal opcodes would just map to other documented instructions (e.g. 0x60 - 0x6f --> 0x70 – 0x7F);
  ;; while a few others such as 'SALC' actually did something useful.
  ;; However, a real 8086 (or anything earlier than 80186) would do nothing when encountering a truly invalid opcode.
  ;; This emulator aims to be fully compatible with the original 8086, so it supports the redundant opcodes or others like 'SALC'.
  (func $UD (; illegal instruction ;)
    nop
  )

  (func $0xd6 (; SALC ;)
    (if (global.get $CF)
      (then
        i32.const 0xFF
        global.set $AL
      )
      (else
        i32.const 0x00
        global.set $AL
      )
    )
  )


)
