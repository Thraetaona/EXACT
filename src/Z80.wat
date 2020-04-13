;; Module-level documentation (Overview) resides in the 'README.md' file.


(module $cpu
  (; Memory Section ;)
  ;; It is possible to define memory within webassembly like this "(memory 1 16384 shared)",
  ;; however, we currently define it in the host environment and simply export it to this module.
  ;; Where it's defined has no effect on performance, it is purely done to keep the emulator 'modular'
  ;; in a way that it expects memory, basic IO and other components to be provided externally;
  ;; just as a real, physical Z80 would.


  (; Import Section ;)
  (import "env" "memory" (memory 1 16384 shared))


  (; Export Section ;)
  (export "start" (func $start))


  (; Global Section ;)
  (;--- callback function typedefs ---;)
  typedef uint64_t (*tick_t)(int num_ticks, uint64_t pins, void* user_data);
  typedef int (*trap_t)(uint16_t pc, uint32_t ticks, uint64_t pins, void* trap_user_data);

  (;--- address bus pins ---;)
  (global $A0 i32 (1ULL<<0)
  (global $A1 i32 (1ULL<<1)
  (global $A2 i32 (1ULL<<2)
  (global $A3 i32 (1ULL<<3)
  (global $A4 i32 (1ULL<<4)
  (global $A5 i32 (1ULL<<5)
  (global $A6 i32 (1ULL<<6)
  (global $A7 i32 (1ULL<<7)
  (global $A8 i32 (1ULL<<8)
  (global $A9 i32 (1ULL<<9)
  (global $A10 i32 (1ULL<<10)
  (global $A11 i32 (1ULL<<11)
  (global $A12 i32 (1ULL<<12)
  (global $A13 i32 (1ULL<<13)
  (global $A14 i32 (1ULL<<14)
  (global $A15 i32 (1ULL<<15)

  (;--- data bus pins ------;)
  (global $D0 i32 (1ULL<<16)
  (global $D1 i32 (1ULL<<17)
  (global $D2 i32 (1ULL<<18)
  (global $D3 i32 (1ULL<<19)
  (global $D4 i32 (1ULL<<20)
  (global $D5 i32 (1ULL<<21)
  (global $D6 i32 (1ULL<<22)
  (global $D7 i32 (1ULL<<23)

  (;--- control pins ---;)

  (; system control pins ;)
  (global $M1 i32 (1ULL<<24)       (; machine cycle 1 ;)
  (global $MREQ i32 (1ULL<<25)       (; memory request ;)
  (global $IORQ i32 (1ULL<<26)       (; input/output request ;)
  (global $RD i32 (1ULL<<27)       (; read ;)
  (global $WR i32 (1ULL<<28)       (; write ;)
  (global $RFSH i32 (1ULL<<32)       (; refresh ;)
  (global $CTRL_MASK i32 (M1|MREQ|IORQ|RD|WR|RFSH)

  (; CPU control pins ;)
  (global $HALT i32 (1ULL<<29)       (; halt state ;)
  (global $INT i32 (1ULL<<30)       (; interrupt request ;)
  (global $NMI i32 (1ULL<<31)       (; non-maskable interrupt ;)

  (; up to 7 wait states can be injected per machine cycle ;)
  (global $WAIT0 i32 (1ULL<<34)
  (global $WAIT1 i32 (1ULL<<35)
  (global $WAIT2 i32 (1ULL<<36)
  (global $WAIT_SHIFT i32 (34)
  (global $WAIT_MASK i32 (WAIT0|WAIT1|WAIT2)

  (; interrupt-related 'virtual pins', these don't exist on the Z80 ;)
  (global $IEIO i32 (1ULL<<37)      (; unified daisy chain 'Interrupt Enable In+Out' ;)
  (global $RETI i32 (1ULL<<38)      (; cpu has decoded a RETI instruction ;)

  (; bit mask for all CPU bus pins ;)
  (global $PIN_MASK i32 ((1ULL<<40)-1)

  (;--- status indicator flags ---;)
  (global $CF i32 (1<<0)           (; carry ;)
  (global $NF i32 (1<<1)           (; add/subtract ;)
  (global $VF i32 (1<<2)           (; parity/overflow ;)
  (global $PF i32 $VF
  (global $XF i32 (1<<3)           (; undocumented bit 3 ;)
  (global $HF i32 (1<<4)           (; half carry ;)
  (global $YF i32 (1<<5)           (; undocumented bit 5 ;)
  (global $ZF i32 (1<<6)           (; zero ;)
  (global $SF i32 (1<<7)           (; sign ;)

  (; Table Section ;)
  ;; Reference: http://z80-heaven.wikidot.com/opcode-reference-chart
  (table $opcodes 255 255 funcref) (elem (i32.const 0) 
    $0x00 $0x01 $0x02 $0x03 $0x04 $0x05 $0x06 $0x07 $0x08 $0x09 $0x0a $0x0b $0x0c $0x0d $0x0e $0x0f
    $0x10 $0x11 $0x12 $0x13 $0x14 $0x15 $0x16 $0x17 $0x18 $0x19 $0x1a $0x1b $0x1c $0x1d $0x1e $0x1f
    $0x20 $0x21 $0x22 $0x23 $0x24 $0x25 $0x26 $0x27 $0x28 $0x29 $0x2a $0x2b $0x2c $0x2d $0x2e $0x2f
    $0x30 $0x31 $0x32 $0x33 $0x34 $0x35 $0x36 $0x37 $0x38 $0x39 $0x3a $0x3b $0x3c $0x3d $0x3e $0x3f
    $0x40 $0x41 $0x42 $0x43 $0x44 $0x45 $0x46 $0x47 $0x48 $0x49 $0x4a $0x4b $0x4c $0x4d $0x4e $0x4f
    $0x50 $0x51 $0x52 $0x53 $0x54 $0x55 $0x56 $0x57 $0x58 $0x59 $0x5a $0x5b $0x5c $0x5d $0x5e $0x5f
    $0x60 $0x61 $0x62 $0x63 $0x64 $0x65 $0x66 $0x67 $0x68 $0x69 $0x6a $0x6b $0x6c $0x6d $0x6e $0x6f
    $0x70 $0x71 $0x72 $0x73 $0x74 $0x75 $0x76 $0x77 $0x78 $0x79 $0x7a $0x7b $0x7c $0x7d $0x7e $0x7f
    $0x80 $0x81 $0x82 $0x83 $0x84 $0x85 $0x86 $0x87 $0x88 $0x89 $0x8a $0x8b $0x8c $0x8d $0x8e $0x8f
    $0x90 $0x91 $0x92 $0x93 $0x94 $0x95 $0x96 $0x97 $0x98 $0x99 $0x9a $0x9b $0x9c $0x9d $0x9e $0x9f
    $0xa0 $0xa1 $0xa2 $0xa3 $0xa4 $0xa5 $0xa6 $0xa7 $0xa8 $0xa9 $0xaa $0xab $0xac $0xad $0xae $0xaf
    $0xb0 $0xb1 $0xb2 $0xb3 $0xb4 $0xb5 $0xb6 $0xb7 $0xb8 $0xb9 $0xba $0xbb $0xbc $0xbd $0xbe $0xbf
    $0xc0 $0xc1 $0xc2 $0xc3 $0xc4 $0xc5 $0xc6 $0xc7 $0xc8 $0xc9 $0xca $0xcb $0xcc $0xcd $0xce $0xcf
    $0xd0 $0xd1 $0xd2 $0xd3 $0xd4 $0xd5 $0xd6 $0xd7 $0xd8 $0xd9 $0xda $0xdb $0xdc $0xdd $0xde $0xdf
    $0xe0 $0xe1 $0xe2 $0xe3 $0xe4 $0xe5 $0xe6 $0xe7 $0xe8 $0xe9 $0xea $0xeb $0xec $0xed $0xee $0xef
    $0xf0 $0xf1 $0xf2 $0xf3 $0xf4 $0xf5 $0xf6 $0xf7 $0xf8 $0xf9 $0xfa $0xfb $0xfc $0xfd $0xfe $0xff
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
  

)
