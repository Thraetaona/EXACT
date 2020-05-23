;; EXACT: Emulating X86 iAPX CPU on NeT
;; Copyright (C) 2020  Fereydoun Memarzanjany
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.
;;
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
  ;;
  ;;
  ;; Be aware that a few -Bytes- could be saved by using a segmented module along with offsets or branching;
  ;; However, that would significantly lower performance and complicate the codebase with no Reasonable gains.
  ;; Linear memory layout:
  ;; (Each number represents a byte and each WASM memory page equqls 64KiB.)
  ;;
  ;; [0, 7]         => General registers.
  ;; (7, 15]        => Index registers.
  ;; (15, 23]       => Segment registers.
  ;; (23, 39]       => Flag registers.
  ;; (39, 295]      => Array holding Instruction lengths.
  ;; (295, 1048871] => 1Mib of Random-access memory.
  ;; (1048871, ] => 



  (; 
   ; Import Section
   ;)
  (import "env" "memory" (memory 16 16384))



  (; 
   ; Export Section
   ;)
  (export "start" (func $start))
  (export "memory" (memory 0))
  (export "IP" (global $IP))


  (; 
   ; Global Section
   ;)
  (; These are instantiation-time global -constants-, equivalent to static variables in C and C++, solely for convenience.    ;
   ; They are accessed through $register.set/get interfaces; to ensure efficient and reliable emulation of decoded registers. ;)
  ;; 16-Bit general purpose registers (Divided into Low / High)
  (global $AX i32 (i32.const 0)) ;; 0; Accumulator (divided into AL / AH)
  (global $CX i32 (i32.const 1)) ;; 1; Count (divided into CL / CH)
  (global $DX i32 (i32.const 2)) ;; 2; Data (divided into DL / DH)
  (global $BX i32 (i32.const 3)) ;; 3; Base (divided into BL / BH)
  ;; 16-Bit Index registers 
  (global $SP i32 (i32.const 4)) ;; 4; Stack pointer 
  (global $BP i32 (i32.const 5)) ;; 5; Base pointer 
  (global $SI i32 (i32.const 6)) ;; 6; Source index
  (global $DI i32 (i32.const 7)) ;; 7; Destination index

  ;; 8-Bit decoded general purpose registers
  (global $AL i32 (i32.const 0)) ;; 0; Accumulator low
  (global $CL i32 (i32.const 1)) ;; 1; Count low
  (global $DL i32 (i32.const 2)) ;; 2; Data low
  (global $BL i32 (i32.const 3)) ;; 3; Base low
  (global $AH i32 (i32.const 4)) ;; 4; Accumulator High
  (global $CH i32 (i32.const 5)) ;; 5; Count High
  (global $DH i32 (i32.const 6)) ;; 6; Data High
  (global $BH i32 (i32.const 7)) ;; 7; Base high

  ;; Segment registers
  (global $ES i32 (i32.const 0)) ;; 0; Extra segment
  (global $CS i32 (i32.const 1)) ;; 1; Code segment
  (global $SS i32 (i32.const 2)) ;; 2; Stack segment
  (global $DS i32 (i32.const 3)) ;; 3; Data segment

  ;; Status Flag Registers
  (global $CF i32 (i32.const 0)) ;; bit 0; Carry (Borrow) flag
  (global $PF i32 (i32.const 2)) ;; bit 2; Parity flag
  (global $AF i32 (i32.const 4)) ;; bit 4; Adjust (Auxiliary) flag
  (global $ZF i32 (i32.const 6)) ;; bit 6; Zero flag
  (global $SF i32 (i32.const 7)) ;; bit 7; Sign flag
  (global $OF i32 (i32.const 11)) ;; bit 11; Overflow flag
  ;; Control Flag Registers
  (global $TF i32 (i32.const 8)) ;; bit 8; Trap flag
  (global $IF i32 (i32.const 9)) ;; bit 9; Interrupt flag
  (global $DF i32 (i32.const 10)) ;; bit 10; Direction flag


  (; The followings are actual mutable global -variables-.  Unlike the above globals these are accessed directly. ;)
  ;; Program counter
  (global $IP (mut i32) (i32.const 0)) ;; 0; Instruction pointer



  (; 
   ; Data Section
   ;)
  ;; Array for holding all registers.
  ;;
  ;; WebAssembly is low-endian, although endianness does not matter inside a register, as they are byte-accessible rather than byte-addressable.
  ;; Also, it appears that the 8086 had some 'reserved' flags that were always(?) set to 1; UD is used to represent those.
  (data $registers (i32.const 0)
    (;[A X]    [C X]   [D  X]    [B X]   Note:"\XLow\XHigh" ;)
    "\00\00" "\00\00" "\00\00" "\00\00"          (; General ;)
    (;[S P]    [B P]   [S  I]    [D I]                      ;)
    "\00\00" "\00\00" "\00\00" "\00\00"          (;  Index  ;)
    (;[E S]    [C S]   [S  S]    [D S]                      ;)  
    "\00\00" "\00\00" "\00\00" "\00\00"          (; Segment ;)
    (;CF    UD    PF    UD    AF    UD    ZF    SF          ;)
    "\00" "\01" "\00" "\01" "\00" "\01" "\00" "\00" (; Flag ;)
    (;TF    IF    DF    OF    UD    UD    UD    UD          ;)
    "\00" "\00" "\00" "\00" "\01" "\01" "\01" "\01" (; Flag ;)
  )

  ;; Array for holding Instruction lengths.
  (data $opcode_lenghts (i32.const 40)
    (; 0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F     / ;)
    "\02" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; 0 ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; 1 ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; 2 ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; 3 ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; 4 ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; 5 ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; 6 ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; 7 ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; 8 ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; 9 ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; A ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; B ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; C ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; D ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; E ;)
    "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" "\01" (; F ;)
  )

  ;; 1Mib of Random-access memory.
  (data $ram (i32.const 296)
  )



  (; 
   ; Table & Element Section
   ;)
  ;; lookup table for dynamic dispatch of opcodes readen from hex code.
  (table $opcodes 256 256 funcref) (elem (i32.const 0)
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
   ; Start & Main Section
   ;)
  (func $start

    (call $set_aoc
      (i32.const 4)
      (i32.const -120)
      (i32.const 023)
    )
    drop
  )



  (; 
   ; Code Section
   ;)
  (; Helper functions ;)
  (; Interfaces to work with registers, the input is sanitized to ensure that other memory locations are not revealed and to prevent overlaps. ;)
  ;; Stores a 16-Bit value in an index or general-purpose register.
  (func $register.general.set16 (param $bit i32) (param $value i32)
    (i32.store16 offset=0 align=1
      (i32.mul
        (i32.rem_u
          (local.get $bit)
          (i32.const 8)
        )
        (i32.const 2)
      )
      (local.get $value)
    )
  )
  ;; Retrieves a previously stored 16-Bit value from the specified register.
  (func $register.general.get16 (param $bit i32) 
                                (result i32)
    (i32.load16_s offset=0 align=1
      (i32.mul
        (i32.rem_u
          (local.get $bit)
          (i32.const 8)
        )
        (i32.const 2)
      )
    )
  )
  ;; According to Intel's documentations Each register is assigned a number for encoding (Global constants section), 
  ;; However as all registers are stored in memory, 8-Bit registers do not follow the same addressing scheme.
  ;; Given that the registers are stored in the low-endian format (i.e., AH comes right after AL), but
  ;; during encoding AH does not come right after AL (AH is 4 and AL is 0), they have to be decoded
  ;; using a table that maps Intel's addresses onto ours, this is done through branching.
  ;; register's assigned 0 to 3 are multiplied by 2; While the rest should be pointing to 1, 3, 5 and 7, respectively. 
  (func $register.general.decode8 (param $bit i32)
                                  (result i32)
  (block (block (block (block (block (local.get $bit)
            (br_table
              0 0 0 0   ;; bit == {0, 1, 2, 3} --> (br 0)[0]
              1         ;; bit == 4 --> (br 4)[1]
              2         ;; bit == 5 --> (br 5)[3]
              3         ;; bit == 6 --> (br 6)[5]
              4         ;; 0 > bit OR result >= 7 --> (br 7 (Default))[7]
              ))
            ;; Target for (br 0)
            (return (i32.mul (local.get $bit) (i32.const 2))))
          ;; Target for (br 1)
          (return (i32.const 1)))
        ;; Target for (br 2)
        (return (i32.const 3)))
      ;; Target for (br 3)
      (return (i32.const 5)))
    ;; (Default) Target for (br 7)
    (return (i32.const 7))
  )
  ;; Stores a 8-Bit value in a general-purpose register.
  (func $register.general.set8 (param $bit i32) (param $value i32)
    (i32.store8 offset=0 
      (call $register.general.decode8 (local.get $bit)) 
      (local.get $value)
    )
  )
  ;; Retrieves a previously stored 8-Bit value value from the specified register.
  (func $register.general.get8 (param $bit i32) 
                               (result i32)
    (i32.load8_s offset=0
      (call $register.general.decode8 (local.get $bit)) 
    )
  )

  ;; Stores a 16-Bit value in a segment register.
  (func $register.segment.set (param $bit i32) (param $value i32)
    (i32.store16 offset=16 align=1
      (i32.mul
        (i32.rem_u
          (local.get $bit)
          (i32.const 4)
        )
        (i32.const 2)
      )
      (local.get $value)
    )
  )
  ;; Retrieves a previously stored 16-Bit value from the specified segment register.
  (func $register.segment.get (param $bit i32) 
                              (result i32)
    (i32.load16_s offset=16 align=1
      (i32.mul
        (i32.rem_u
          (local.get $bit)
          (i32.const 4)
        )
        (i32.const 2)
      )
    )
  )

  ;; Stores a 1-Bit value in a flag register.
  (func $register.flag.set (param $bit i32) (param $value i32)
    (i32.store8 offset=24
      (i32.rem_u
        (local.get $bit)
        (i32.const 16)
      )
      (select (i32.const 1) (i32.const 0)
              (local.get $value))
    )
  )
  ;; Retrieves a previously stored 1-Bit value value from the specified flag register.
  (func $register.flag.get (param $bit i32) 
                           (result i32)
    (i32.load8_s offset=24
      (i32.rem_u
        (local.get $bit)
        (i32.const 16)
      )
    )
  )
  

  (;func $ram.set (param $address i32) (param $offset i32) (param $value i32)
    (i32.store16 offset=0 align=1
      (i32.mul
        (i32.rem_u
          (local.get $bit)
          (i32.const 8)
        )
        (i32.const 2)
      )
      (local.get $value)
    )
  )
  (func $ram.get (param $address i32) (param $offset i32)
                 (result i32)
    (i32.load8_s offset=296
      (i32.rem_u
        (local.get $bit)
        (i32.const 16)
      )
    )
  ;)


  ;; Sets Zero/Sign/Parity flags accordingly to the resulting value from math operations, does not 'Consume' the value.
  (func $set_zsp (param $value i32) 
                 (result i32)
    ;; If the value equals 0 then ZF is set to 1; 0 otherwise.
    (call $register.flag.set
      (global.get $ZF)
      (select (i32.const 0) (i32.const 1)
              (local.get $value))
    )

    ;; If the high-order bit of the value is a 1 then SF is set to 1; 0 otherwise. (Two's complement notation)
    (call $register.flag.set
      (global.get $SF)
      (i32.shr_u (local.get $value) (i32.const 15))
    )

    ;; If the value has even parity (an even number of 1-Bits) PF is set to 1; 0 otherwise.
    (call $register.flag.set
      (global.get $PF)
      (i32.xor ;; This will negate the outcome (as if i32.not existed).
        (i32.rem_u
          (i32.popcnt (local.get $value))
          (i32.const 2)
        )
        (i32.const 1)
      )
    )

    (return (local.get $value))
  )
  
  ;; Sets Adjust/Overflow/Carry flags just like above.
  ;; Be aware that $set_zsp has to be called before this; otherwise this might set flags incorrectly.
  (func $set_aoc (param $value i32) (param $destination i32) (param $source i32)
                 (result i32)
    ;; If the result of a signed operation is too large to be represented in 8-Bits, Then OF is set to 1; 0 otherwise.
    ;; http://teaching.idallen.com/dat2343/10f/notes/040_overflow.txt explains Carry & Overflow flags in a very detailed manner.
    (call $register.flag.set
      (global.get $OF)
      (block (block
        (i32.add ;; Incrementing by 1 will ensure that branching works properly (i.e., not branching for less than zero).
          (i32.sub ;; If the result equals -1 or 2, then an overflow happend.
            (i32.add ;; If the result is 2 both values were Negative; if it was 0 then both were Positive; otherwise only one of them was.
              (i32.shr_u (local.get $destination) (i32.const 15))
              (i32.shr_u (local.get $source) (i32.const 15))
            )
            (i32.shr_u (local.get $value) (i32.const 15)) ;; Could also use Sign Flag's value if $set_zsp is guaranteed to be called beforehand.
          )
          (i32.const 1)
        )
        (br_table
          1    ;; result == 0 --> (br 1)[Overflow]
          0 0  ;; result == {1, 2} --> (br 0)[0]
          1    ;; 0 > result OR result >= 3 --> (br 1 (Default))[Overflow]
          ))
        ;; Target for (br 0)
        (return (i32.const 0)))
      ;; (Default) Target for (br 1)
      (return (i32.const 1))
    )

    ;; If the result of a signed operation is too large to be represented in 8-Bits, Then OF is set to 1; 0 otherwise.
    (call $register.flag.set
      (global.get $CF)
      (i32.const 65535)
    )
  )


  (; Opcode backends ;)
  ;; adds a value (plus an optional carry flag) to a register or memory.
  (;func $ADD (param $destination i32) (param $source i32) (param $carry i32) 
             (result i32)
    (i32.add
      (i32.add (local.get $destination) (local.get $source))
      (select (global.get $CF) (i32.const 0)
              (local.get $carry))
    )
    call $set_zsp ;; This will also return (i.e., won't 'Consume') the result from the above ADD function.
    (; above result ;) (local.get $destination) (local.get $source)
    call $set_aoc

    ;; It's not possible to pass global variables as function arguments,
    ;; so this function simply returns the resulting number and sets status flags accordingly.  
    ;; setting destination to the said number is done in opcodes.
  ;)


  (; Opcodes ;)
  (func $0x00 (; ADD Eb, Gb ;) (;
    i32.const 0
    call $ADD
    global.set $ ;)
  )
  (func $0x01 (; ADD Ev, Gv ;) (;
    i32.const 0
    call $ADD
    global.set $ ;)
  )
  (func $0x02 (; ADD Gb, Eb ;) (;
    i32.const 0
    call $ADD
    global.set $ ;)
  )
  (func $0x03 (; ADD Gv, Ev ;) (;
    i32.const 0
    call $ADD
    global.set $ ;)
  )
  (func $0x04 (; ADD AL, Ib;) (;
    (call $register.general.set8 
      (global.get $AL) 
      (call $ADD
        (global.get $AL) 

        (i32.const 0)
      )
    ;)
  )
  (func $0x05 (; ADD AX, Iv ;) (;
    (call $register.general.set16 
      (global.get $AX) 
      (call $ADD
        (global.get $AX)

        (i32.const 0)
      )
    ;)
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
  ;; This emulator aims to be FULLY compatible only (i.e.,. no co-processors) with the original 8086, so it supports the 
  ;; redundant opcodes or others like 'SALC'.  Also, several opcodes (e.g. 0xd8 - 0xdf) are only valid when a co-processor like x87 is present; 
  ;; but since we are emulating this on fast, modern hardware, and co-processors were very rare and expensive back then; 
  ;; emulating a 8087 is out of this project's scope, and therefore invalid.
  (func $UNDF (; illegal instruction ;)
    nop
  )

  (func $0x0f (; POP CS ;)
    ;; work-in-progress
  )

  ;; this opcode sets AL to 256 if the carry flag is set; 0 otherwise.
  (func $0xd6 (; SALC ;)
    (call $register.general.set8 
      (global.get $AL)
      (select (i32.const 0xFF) (i32.const 0x00)
              (call $register.general.get8 (global.get $CF)))
    )
  )


)
