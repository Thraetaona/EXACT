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
;;
;; Basic module-level Overview resides in the 'README.md' file.
;;
;; Assemble with 'wat2wasm ./src/8086.wat -o ./src/8086.wasm'



;; WebAssembly's Normative documentation can be confusing at first; given the lack of examples, too, it's best to refer to these links
;; for questions regarding WASM's text syntax and WebAssembly in general.
;; (Obviously there are also a number of blog posts and questions on different forums related to WebAssembly.
;;  however, this is just a compilation of the most definitive ones)
;;
;;
;; To assembly this text representation, you'll have to use WebAssembly's official toolkit called 'wabt' 
;; which should already be available in your distribution's repository, alternatively you could locally compile it:
;; https://github.com/WebAssembly/wabt
;;
;; The official testsuite could be useful if all you need is an example of the syntax:
;; https://github.com/WebAssembly/testsuite/find/master
;;
;; The output from the backend of languages that can be compiled to WebAssembly could also assist in debugging:
;; https://mbebenita.github.io/WasmExplorer/
;;
;; All instructions along with their OpCodes and notes are available here:
;; https://wiki.freepascal.org/WebAssembly/Instructions
;;
;; The old WebAssembly documentation explains the purpose of each instruction:
;; https://webassembly.github.io/spec/core/syntax/instructions.html
;;
;; For information about how numbers and values are encoded in WebAssembly:
;; https://webassembly.github.io/spec/core/binary/values.html
;; https://en.wikipedia.org/wiki/LEB128
;;
;; On memory management and Binary sections:
;; https://rsms.me/wasm-intro
;;
;; It's good to have a look at WebAssembly from these perspectives, too:
;; http://troubles.md/wasm-is-not-a-stack-machine/
;; https://www.virusbulletin.com/virusbulletin/2018/10/dark-side-webassembly/
;;
;; Also, it's worth mentioning that the text representation underwent some changes a while ago (Old syntax is still valid):
;; https://github.com/WebAssembly/spec/issues/884#issuecomment-426433329
;;
;; The new normative documentations could be useful once you get more familiar with WebAssembly:
;; https://webassembly.github.io/spec/core/syntax/instructions.html
;;
;; And lastly, if interested, you could also read an in-depth definition of it in WebAssembly's Core Specifications which should clarify nearly everything:
;; https://www.w3.org/TR/wasm-core-1/
;;
;;
;;
;; As for Intel's 8086, the following sources could be helpful.
;;
;;
;; For undocumented and duplicate OpCodes:
;; http://www.os2museum.com/wp/undocumented-8086-opcodes/
;; http://www.os2museum.com/wp/undocumented-8086-opcodes-part-i/
;; 
;; Detailed analysis of each instruction:
;; https://www.gabrielececchetti.it/Teaching/CalcolatoriElettronici/Docs/i8086_instruction_set.pdf
;; https://en.wikipedia.org/wiki/X86_instruction_listings?#Original_8086/8088_instructions 
;;
;; OpCode maps (second link covers undocumented ones as well):
;; http://www.mlsite.net/8086/
;; https://sandpile.org/x86/opc_1.htm
;;
;; Flag registers (including reserved bits):
;; https://en.wikipedia.org/wiki/FLAGS_register
;; https://www.geeksforgeeks.org/flag-register-8086-microprocessor/
;; http://teaching.idallen.com/dat2343/10f/notes/040_overflow.txt
;;
;; finally, for difficulties regarding the complicated encoding/decoding process:
;; http://aturing.umcs.maine.edu/~meadow/courses/cos335/8086-instformat.pdf
;; https://www.includehelp.com/embedded-system/instruction-format-in-8086-microprocessor.aspx
;; https://www.ic.unicamp.br/~celio/mc404s2-03/addr_modes/intel_addr.html#HEADING2-35
;; https://en.wikipedia.org/wiki/Intel_8086
(module $cpu
  (; 
   ; Memory Section
   ;)
  ;; It is possible to define the memory within webassembly like this "(memory 17 17)",
  ;; however, we currently define it in the host environment and simply export it to this module.
  ;; Where it's defined has no effect on performance, it is purely done to keep the emulator 'modular',
  ;; in a way that it expects memory, basic IO and other components to be provided externally;
  ;; just as a real, physical 8086 would.
  ;;
  ;;
  ;; This entire module on it's own should only be using less than 40 bytes of linear memory which is only a fraction
  ;; of what's specified above (17 pages), the majority of it is dedicated to the 1MiB of RAM for emulating User programs.
  ;; Be aware that even a few extra _Bytes_ could be saved by using a segmented module along with offsets or branching;
  ;; However, that would significantly lower performance and complicate the codebase with no Reasonable gains.
  ;; Linear memory layout:
  ;; (numbers represents bytes and each WASM memory page equqls 64KiB.)
  ;;
  ;; [0, 7]         => General registers.
  ;; (7, 15]        => Index registers.
  ;; (15, 23]       => Segment registers.
  ;; (23, 39]       => Flag registers.
  ;; (39, 1048615]  => 1Mib of Random-access memory.



  (; 
   ; Import Section
   ;)
  (import "env" "memory" (memory 17 17))



  (; 
   ; Export Section
   ;)
  (export "memory" (memory 0))
  (export "run" (func $run))
  (export "IP" (global $IP))
  (export "programLength" (global $program_length))


  (; 
   ; Global Section
   ;)
  (; These are instantiation-time global _constants_, equivalent to static variables in C and C++, merely for convenience.    ;
   ; They are accessed through $register.set/get interfaces; to ensure efficient and reliable emulation of decoded registers. ;)
  ;; 16-Bit general purpose registers (Divided into Low / High)
  (global $AX i32 (i32.const 0)) ;; 000b; Accumulator (divided into AL / AH)
  (global $CX i32 (i32.const 1)) ;; 001b; Count (divided into CL / CH)
  (global $DX i32 (i32.const 2)) ;; 010b; Data (divided into DL / DH)
  (global $BX i32 (i32.const 3)) ;; 011b; Base (divided into BL / BH)
  ;; 16-Bit Index registers 
  (global $SP i32 (i32.const 4)) ;; 100b; Stack pointer 
  (global $BP i32 (i32.const 5)) ;; 101b; Base pointer 
  (global $SI i32 (i32.const 6)) ;; 110b; Source index
  (global $DI i32 (i32.const 7)) ;; 111b; Destination index

  ;; 8-Bit decoded general purpose registers
  (global $AL i32 (i32.const 0)) ;; 000b; Accumulator low
  (global $CL i32 (i32.const 1)) ;; 001b; Count low
  (global $DL i32 (i32.const 2)) ;; 010b; Data low
  (global $BL i32 (i32.const 3)) ;; 011b; Base low
  (global $AH i32 (i32.const 4)) ;; 100b; Accumulator High
  (global $CH i32 (i32.const 5)) ;; 101b; Count High
  (global $DH i32 (i32.const 6)) ;; 110b; Data High
  (global $BH i32 (i32.const 7)) ;; 111b; Base high

  ;; Segment registers
  (global $ES i32 (i32.const 0)) ;; 00b; Extra segment
  (global $CS i32 (i32.const 1)) ;; 01b; Code segment
  (global $SS i32 (i32.const 2)) ;; 10b; Stack segment
  (global $DS i32 (i32.const 3)) ;; 11b; Data segment

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


  (; The followings are actual mutable global _variables_.  Unlike the above globals these are accessed directly. ;)
  ;; Program counter
  (global $IP (mut i32) (i32.const 0)) ;; 0; Instruction pointer
  ;; Length of the current program (Number of bytes) that is loaded in memory.  We can not use any methods other than assigning a variable
  ;; to program's length. As an example, if we were to use a 'Sentinent byte' (i.e., Pre-defining a value to represent 'Undefined' in JavaScript
  ;; and then inserting it at the end of readen binaries (Since there aren't any _efficient_ ways to check for JavaScript's 'Undefined' in WebAssembly)), 
  ;; then we could not guarantee the correct emulation of non-standard program, also that would add an overhead of 1 byte; to further clarify,
  ;; suppose we are choosing a Sentinent value (byte) that is not a legal and documented OpCode, that leaves us with 23[1] out of 256 (0xff) options,
  ;; but the 8086 (And anything earlier than a 80186) do nothing upon encountering an illegal OpCode (Basically a no-op), now if the user or the assembler
  ;; decides to put one of those illegal OpCodes in their binary file, our emulator would immediately terminate the program once it saw that Sentinent byte
  ;; (False positive); while the expected behaviour was to ignore the said byte and continue execution.
  ;;
  ;; [1]: the number is actually 0.  considering that some illegal OpCodes such as 'SALC' actually did something useful, we emulate those, too.
  ;; Other illegal OpCodes either mapped to another one (e.g., 0x60 - 0x6f --> 0x70 – 0x7f), or did not do anything _noticeable_ at all (Like writing
  ;; a register to itself which is pointless); so in reality we could only choose from the ones that simply acted like an extra nop (no operation) and
  ;; well, there aren't any 'Useless' OpCodes available for that purpose.
  (global $program_length (mut i32) (i32.const 0)) ;; a variable representing the size of the current program.

  ;; Mod|Reg|R/M field that is extracted from the byte following most OpCodes with a length higher than 1 (Refer to $parse_address for more information)
  (global $mod (mut i32) (i32.const 0)) ;; mode, varies from 00b to 11b
  (global $reg (mut i32) (i32.const 0)) ;; register, Should range from 000b to 111b
  (global $rm (mut i32) (i32.const 0)) ;; register/memory, Like above, a value that is 000b to 111b

  ;; segment's other than the default $CS can be used for a particular code, $seg_override is set by prefix OpCodes.
  ;; https://en.wikipedia.org/wiki/X86_memory_segmentation#Practices
  ;;
  ;; seg_override is required because it's possible to select $CS as an override, which means that there won't be any other (clean) way
  ;; other than using a separate variable to check for overrides.
  ;; https://www.ngemu.com/threads/emu-decoding-8086-x86-opcodes.155663/post-2094016
  ;;
  ;; However, in case of our emulator, OpCode prefixes are handled no differently from the normal ones.  That significant improves performance
  ;; compared to the naive method which look-up's the same opcode twice.
  (global $seg (mut i32) (i32.const 3)) ;; Current segment override (Only if seg_override is set)
  (global $seg_override (mut i32) (i32.const 0)) ;; Indicates whether $seg's value should be used instead of the default Data Segment

  (global $ea (mut i32) (i32.const 0)) ;; Effective Address calculated using the $compute_ea function



  (; 
   ; Data Section
   ;)
  ;; Array for holding all registers (Except IP).
  ;;
  ;; WebAssembly is low-endian, although endianness does not matter inside a register, as they are byte-accessible rather than byte-addressable.
  ;; Also, it appears that the 8086 had some 'reserved' flags that were always(?) set to 1 by default; 'UD' is used to represent those.
  (data $registers (i32.const 0)
    (;[A X]    [C X]   [D  X]    [B X]   Note:"\XLow\XHigh" ;)
    (;AL\BL    CL\CH    DL\DH    BL\BH                      ;)
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

  ;; 1Mib of Random-access memory.
  (data $ram (i32.const 40)
  )



  (; 
   ; Table & Element Section
   ;)
  ;; lookup table for dynamic dispatch of OpCodes readen from hex code.
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
    $0xd0 $0xd1 $0xd2 $0xd3 $0xd4 $0xd5 $0xd6 $0xd7 $0xd8 $0xd9 $0xda $0xdb $0xdc $0xdd $0xde $0xdf (; D ;)
    $0xe0 $0xe1 $0xe2 $0xe3 $0xe4 $0xe5 $0xe6 $0xe7 $0xe8 $0xe9 $0xea $0xeb $0xec $0xed $0xee $0xef (; E ;)
    $0xf0 $0xf1 $0xf2 $0xf3 $0xf4 $0xf5 $0xf6 $0xf7 $0xf8 $0xf9 $0xfa $0xfb $0xfc $0xfd $0xfe $0xff (; F ;)
  )



  (; 
   ; Start & Main Section
   ;)
  ;; This function (initializer) will run the moment our module has been instantiated, without needing any manual
  ;; invocations.  Such a feature is not needed in our module anyway, so it is wrapped inside block comments for
  ;; future use, considering that it can still be useful during debugging or developing OpCodes.
  (;start
  ;)


  (func $run
    ;; Combination of a block alongside this loop will form a 'do-while' loop.
    (block (loop
      ;; Stops the execution (Jumps out) if the program has reached it's end.
      (br_if 1 (i32.ge_u (global.get $IP) (global.get $program_length)))

      call $execute

      br 0 ;; This will return to the top of this loop.
    ))
  )

  (func $execute
      (call_indirect (block (result i32)
                       (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP)) ;; BIU | fetching instructions from memory
                       (call $step_ip (i32.const 1)) ;; Reading from memory should increment $IP by one.
                     )
      )
  )



  (; 
   ; Code Section
   ;)
  (; Helper functions ;)
  ;; Logical Not (!); This will invert the supplied value, as if an 'i32.not' instruction existed in WebAssembly (e.g., 32 --> 0).
  (func $i32.not (param $value i32)
                 (result i32)
    (return
      (select (i32.const 0) (i32.const 1)
              (local.get $value))
    )
  )
  ;; Similar to above, except that this will negate it's operand (e.g., 32 --> -32).
  (func $i32.neg (param $value i32)
                 (result i32)
    (return
      (i32.sub (i32.const 0) (local.get $value))
    )
  )

  ;; This will sign extend a 8-Bit number to a 16-Bit integer.
  ;; https://github.com/WebAssembly/sign-extension-ops/blob/master/proposals/sign-extension-ops/Overview.md
  (func $i16.extend8_s (param $value i32)
                       (result i32)
    (return
      (i32.shr_s
        (i32.shl
          (local.get $value)
          (i32.const 24)
        )
        (i32.const 24)
      )
    )
  )

  ;; Two's complement addition of 2 16-Bit numbers.
  (func $i16.add (param $destination i32) (param $source i32)
                 (result i32)
    (return
      (i32.and
        (i32.add
          (local.get $destination)
          (local.get $source)
        )
        (i32.const 65535)
      )
    )
  )
  ;; Two's complement addition of 2 8-Bit numbers.
  (func $i8.add (param $destination i32) (param $source i32)
                (result i32)
    (return
      (i32.and
        (i32.add
          (local.get $destination)
          (local.get $source)
        )
        (i32.const 255)
      )
    )
  )


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
    (i32.load16_u offset=0 align=1
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
  ;; However as all registers (Except IP) are stored in memory, 8-Bit registers do not follow the same addressing scheme.
  ;; Given that the registers are stored in the low-endian format (i.e., AH comes right after AL), but
  ;; during encoding AH does not come right after AL (AH is 4 and AL is 0), they have to be decoded
  ;; using a table that maps Intel's addresses onto ours, this is done through branching.
  ;; register's assigned 0 to 3 are multiplied by 2; While the rest should be pointing to 1, 3, 5 and 7, respectively. 
  (func $register.general.decode8 (param $bit i32)
                                  (result i32)
  (block (block (block (block (block (local.get $bit)
            (br_table
              0 0 0 0   ;; bit == [0, 3] --> (br 0)[bit * 2]
              1         ;; bit == {100b} --> (br 1)[1]
              2         ;; bit == {101b} --> (br 2)[3]
              3         ;; bit == {110b} --> (br 3)[5]
              4         ;; 000b > bit OR bit >= 111b --> (br 4 (Default))[7]
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
    (i32.load8_u offset=0
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
    (i32.load16_u offset=16 align=1
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
    (i32.load8_u offset=24
      (i32.rem_u
        (local.get $bit)
        (i32.const 16)
      )
    )
  )


  (; Interfaces to work with RAM, available in 16 and 8 bit variants. ;)
  ;; This will calculate a physical address from a logical one.
  (func $ram.decode (param $address i32) (param $offset i32)
                    (result i32)
    (return
      (i32.add
        (i32.shl 
          (i32.and (local.get $address) (i32.const 65535))
          (i32.const 4)
        )
        (i32.and (local.get $offset) (i32.const 65535))
      )
    )                   
  )

  (; The following functions directly write to the provided (effective) address, this helps to reduce redundancy. ;)
  (func $ram.direct_write16 (param $address i32) (param $value i32)
    (i32.store16 offset=40
      (i32.and (local.get $address) (i32.const 1048575))
      (local.get $value)
    )
  )
  (func $ram.direct_read16 (param $address i32)
                           (result i32)
    (i32.load16_u offset=40
      (i32.and (local.get $address) (i32.const 1048575))
    )
  )
  (func $ram.direct_write8 (param $address i32) (param $value i32)
    (i32.store8 offset=40
      (i32.and (local.get $address) (i32.const 1048575))
      (local.get $value)
    )
  )
  (func $ram.direct_read8 (param $address i32)
                          (result i32)
    (i32.load8_u offset=40
      (i32.and (local.get $address) (i32.const 1048575))
    )
  )

  ;; Stores a 16-Bit value in a given logical address.
  (func $ram.write16 (param $address i32) (param $offset i32) (param $value i32)
    (call $ram.direct_write16
      (call $ram.decode (local.get $address) (local.get $offset))
      (local.get $value)
    )
  )
  ;; Retrieves a 16-Bit value from the specified logical address.
  (func $ram.read16 (param $address i32) (param $offset i32)
                    (result i32)
    (call $ram.direct_read16
      (call $ram.decode (local.get $address) (local.get $offset))
    )
  )

  ;; Stores a 8-Bit value in a given logical address.
  (func $ram.write8 (param $address i32) (param $offset i32) (param $value i32)
    (call $ram.direct_write8
      (call $ram.decode (local.get $address) (local.get $offset))
      (local.get $value)
    )
  )
  ;; Retrieves a 8-Bit value from the specified logical address.
  (func $ram.read8 (param $address i32) (param $offset i32)
                   (result i32)
    (call $ram.direct_read8
      (call $ram.decode (local.get $address) (local.get $offset))
    )
  )


  (; These functions are no different from the above ones; except that their operand can be either          ;
   ; (1) a direct Phyiscal Address or (2) a General Register; rather than strictly accepting one type only. ;
   ; Deciding whether it should write to a register of memory is done through checking the value of $mod.   ;)
  ;; Writes a 16-Bit value to a its destination.
  (func $logical_write16 (param $value i32)
    (if (i32.lt_u (global.get $mod) (i32.const 3)) 
      (then
        (call $ram.direct_write16
          (global.get $ea)
          (local.get $value)
        )
      )
      (else
        (call $register.general.set16
          (global.get $rm)
          (local.get $value)
        )
      )
    )
  )
  ;; Reads a 16-Bit value from its destination.
  (func $logical_read16 (result i32)
    (if (result i32) (i32.lt_u (global.get $mod) (i32.const 3)) 
      (then
        (call $ram.direct_read16
          (global.get $ea)
        )
      )
      (else
        (call $register.general.get16 (global.get $rm))
      )
    )
  )

  ;; Writes a 8-Bit value to a 8-Bit destination.
  (func $logical_write8 (param $value i32)
    (if (i32.lt_u (global.get $mod) (i32.const 3)) 
      (then
        (call $ram.direct_write8
          (global.get $ea)
          (local.get $value)
        )
      )
      (else
        (call $register.general.set8
          (global.get $rm)
          (local.get $value)
        )
      )
    )
  )
  ;; Reads a 8-Bit value from a 8-Bit destination.
  (func $logical_read8 (result i32)
    (if (result i32) (i32.lt_u (global.get $mod) (i32.const 3)) 
      (then
        (call $ram.direct_read8
          (global.get $ea)
        )
      )
      (else
        (call $register.general.get8 (global.get $rm))
      )
    )
  )


  (; Interfaces to work with the stack.  In the 8086 PUSH and POP can only work with 16-Bit elements and the stack grows downward in memory. ;)
  ;; Pushes a 16-Bit value onto the stack, decreasing SP in the process.
  (func $push (param $value i32)
    (call $ram.write16
      (call $register.segment.get (global.get $SS))
      (block (result i32)
        (call $register.general.set16 
          (global.get $SP)
          (i32.sub
            (call $register.general.get16 (global.get $SP))
            (i32.const 2)
          )
        )
        (call $register.general.get16 (global.get $SP))
      )
      (local.get $value)
    )
  )
  ;; Gets (Pops) 16-Bit value from the stack, increasing SP.
  (func $pop (result i32)
    (call $ram.read16
      (call $register.segment.get (global.get $SS))
      (block (result i32)
        (call $register.general.get16 (global.get $SP))
        (call $register.general.set16 
          (global.get $SP)
          (i32.add
            (call $register.general.get16 (global.get $SP))
            (i32.const 2)
          )
        )
      )
    )
  )


  ;; This will increment IP by the given amount.
  (func $step_ip (param $value i32)
    (global.set $IP
      (call $i16.add
        (global.get $IP)
        (local.get $value)
      )
    )
  )


  ;; An inline variable function that calculates the effective address based on the content's of $mod and $rm.
  ;; $parse_address has to be called before this; otherwise this may return an incorrect address.
  ;; It uses multiple nested jump tables internally.  The logic should be quite straightforward after reading the below link.
  ;;
  ;; https://www.ic.unicamp.br/~celio/mc404s2-03/addr_modes/intel_addr.html#HEADING2-35
  ;; In general, addressing modes involving $BP will use the Stack Segment by default; Data Segment otherwise.
  ;; The above rule only applies when there are no segment overrides, however.
  ;;
  ;; It's worth mentioning that $compute_ea will only calculate a new address if $mod is less than 11b,
  ;; considering that 11b is dedicated to the 'REG table' and it should already be present in the $rm field.
  ;;
  ;; And lastly, this function has been optimized for speed, neither for memory usage nor code density. 
  (func $compute_ea
    (block (block (block (block (global.get $mod)
          (br_table
              0 ;; mod == {000b} --> (br 0)[R/M table 1 with R/M operand]
              1 ;; mod == {001b} --> (br 1)[R/M table 2 with 8-Bit displacement]
              2 ;; mod == {010b} --> (br 2)[R/M table 3 with 16-Bit displacement]
              3 ;; 000b > mod OR mod >= 011b --> (br 3 (Default))[REG table]
            ))
          ;; Mod target for (br 0)
            (; R/M table 1 with R/M operand ;)
              (block (block (block (block (block (block (block (block (global.get $rm)
                            (br_table
                              0 ;; rm == {000b} --> (br 0)
                              1 ;; rm == {001b} --> (br 1)
                              2 ;; rm == {010b} --> (br 2)[Involves BP]
                              3 ;; rm == {011b} --> (br 3)[Involves BP]
                              4 ;; rm == {100b} --> (br 4)
                              5 ;; rm == {101b} --> (br 5)
                              6 ;; rm == {110b} --> (br 6)
                              7 ;; 000b > rm OR rm >= 111b --> (br 7 (Default))
                            ))
                          ;; R/M table 1 with R/M operand for (br 0)
                          (return (global.set $ea (call $ram.decode 
                              (select (global.get $seg) (call $register.segment.get (global.get $DS))
                                      (global.get $seg_override))
                              (i32.add 
                                (call $register.general.get16 (global.get $BX))
                                (call $register.general.get16 (global.get $SI))
                              )
                            ))
                          ))
                        ;; R/M table 1 with R/M operand for (br 1)
                        (return (global.set $ea (call $ram.decode 
                            (select (global.get $seg) (call $register.segment.get (global.get $DS))
                                    (global.get $seg_override))
                            (i32.add 
                              (call $register.general.get16 (global.get $BX))
                              (call $register.general.get16 (global.get $DI))
                            )
                          ))
                        ))
                      ;; R/M table 1 with R/M operand for (br 2)
                      (return (global.set $ea (call $ram.decode 
                            (select (global.get $seg) (call $register.segment.get (global.get $SS))
                                    (global.get $seg_override))
                            (i32.add 
                              (call $register.general.get16 (global.get $BP))
                              (call $register.general.get16 (global.get $SI))
                            )
                          ))
                      ))
                    ;; R/M table 1 with R/M operand for (br 3)
                    (return (global.set $ea (call $ram.decode 
                          (select (global.get $seg) (call $register.segment.get (global.get $SS))
                                  (global.get $seg_override))
                          (i32.add 
                            (call $register.general.get16 (global.get $BP))
                            (call $register.general.get16 (global.get $DI))
                          )
                        ))
                    ))
                  ;; R/M table 1 with R/M operand for (br 4)
                  (return (global.set $ea (call $ram.decode 
                      (select (global.get $seg) (call $register.segment.get (global.get $DS))
                              (global.get $seg_override))
                      (call $register.general.get16 (global.get $SI))
                    ))
                  ))
                ;; R/M table 1 with R/M operand for (br 5)
                (return (global.set $ea (call $ram.decode 
                    (select (global.get $seg) (call $register.segment.get (global.get $DS))
                            (global.get $seg_override))
                    (call $register.general.get16 (global.get $DI))
                  ))
                ))
              ;; R/M table 1 with R/M operand for (br 6)
              (return (global.set $ea (call $ram.decode
                  (select (global.get $seg) (call $register.segment.get (global.get $DS))
                          (global.get $seg_override)) 
                  (block (result i32)
                    (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
                    (call $step_ip (i32.const 2)) ;; Fetching a 16-Bit displacement should increment $IP by 2.
                  )
                ))
              ))
            ;; (default) R/M table 1 with R/M operand for (br 7)
            (return (global.set $ea (call $ram.decode 
                (select (global.get $seg) (call $register.segment.get (global.get $DS))
                        (global.get $seg_override))
                (call $register.general.get16 (global.get $BX))
              ))
            ))
          (; R/M table 1 with R/M operand ;)
        ;; Mod target for (br 1)
          (; R/M table 2 with 8-Bit displacement ;)
            (block (block (block (block (block (block (block (block (global.get $rm)
                          (br_table
                            0 ;; rm == {000b} --> (br 0)
                            1 ;; rm == {001b} --> (br 1)
                            2 ;; rm == {010b} --> (br 2)[Involves BP]
                            3 ;; rm == {011b} --> (br 3)[Involves BP]
                            4 ;; rm == {100b} --> (br 4)
                            5 ;; rm == {101b} --> (br 5)
                            6 ;; rm == {110b} --> (br 6)[Involves BP]
                            7 ;; 000b > rm OR rm >= 111b --> (br 7 (Default))
                          ))
                        ;; R/M table 2 with 8-Bit displacement for (br 0)
                        (return (global.set $ea (call $ram.decode
                            (select (global.get $seg) (call $register.segment.get (global.get $DS))
                                    (global.get $seg_override))
                            (i32.add
                              (i32.add
                                (call $register.general.get16 (global.get $BX))
                                (call $register.general.get16 (global.get $SI))
                              )
                              (block (result i32)
                                (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
                                (call $step_ip (i32.const 1))
                              )
                            )
                          ))
                        ))
                      ;; R/M table 2 with 8-Bit displacement for (br 1)
                      (return (global.set $ea (call $ram.decode
                          (select (global.get $seg) (call $register.segment.get (global.get $DS))
                                  (global.get $seg_override))
                          (i32.add
                            (i32.add
                              (call $register.general.get16 (global.get $BX))
                              (call $register.general.get16 (global.get $DI))
                            )
                            (block (result i32)
                              (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
                              (call $step_ip (i32.const 1))
                            )
                          )
                        ))
                      ))
                    ;; R/M table 2 with 8-Bit displacement for (br 2)
                    (return (global.set $ea (call $ram.decode
                        (select (global.get $seg) (call $register.segment.get (global.get $SS))
                                (global.get $seg_override))
                        (i32.add
                          (i32.add
                            (call $register.general.get16 (global.get $BP))
                            (call $register.general.get16 (global.get $SI))
                          )
                          (block (result i32)
                            (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
                            (call $step_ip (i32.const 1))
                          )
                        )
                      ))
                    ))
                  ;; R/M table 2 with 8-Bit displacement (br 3)
                  (return (global.set $ea (call $ram.decode
                      (select (global.get $seg) (call $register.segment.get (global.get $SS))
                              (global.get $seg_override))
                      (i32.add
                        (i32.add
                          (call $register.general.get16 (global.get $BP))
                          (call $register.general.get16 (global.get $DI))
                        )
                        (block (result i32)
                          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
                          (call $step_ip (i32.const 1))
                        )
                      )
                    ))
                  ))
                ;; R/M table 2 with 8-Bit displacement for (br 4)
                (return (global.set $ea (call $ram.decode 
                    (select (global.get $seg) (call $register.segment.get (global.get $DS))
                            (global.get $seg_override))
                    (i32.add 
                      (call $register.general.get16 (global.get $SI))
                      (block (result i32)
                        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
                        (call $step_ip (i32.const 1))
                      )
                    )
                  ))
                ))
              ;; R/M table 2 with 8-Bit displacement for (br 5)
              (return (global.set $ea (call $ram.decode 
                  (select (global.get $seg) (call $register.segment.get (global.get $DS))
                          (global.get $seg_override))
                  (i32.add 
                    (call $register.general.get16 (global.get $DI))
                    (block (result i32)
                      (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
                      (call $step_ip (i32.const 1))
                    )
                  )
                ))
              ))
            ;; R/M table 2 with 8-Bit displacement for (br 6)
            (return (global.set $ea (call $ram.decode 
                (select (global.get $seg) (call $register.segment.get (global.get $SS))
                        (global.get $seg_override))
                (i32.add 
                  (call $register.general.get16 (global.get $BP))
                  (block (result i32)
                    (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
                    (call $step_ip (i32.const 1))
                  )
                )
              ))
            ))
          ;; (default) R/M table 2 with 8-Bit displacement for (br 7)
          (return (global.set $ea (call $ram.decode 
              (select (global.get $seg) (call $register.segment.get (global.get $DS))
                      (global.get $seg_override))
              (i32.add 
                (call $register.general.get16 (global.get $BX))
                (block (result i32)
                  (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
                  (call $step_ip (i32.const 1))
                )
              )
            ))
          ))
        (; R/M table 2 with 8-Bit displacement ;)
      ;; Mod target for (br 2)
        (; R/M table 3 with 16-Bit displacement ;)
          (block (block (block (block (block (block (block (block (global.get $rm)
                        (br_table
                          0 ;; rm == {000b} --> (br 0)
                          1 ;; rm == {001b} --> (br 1)
                          2 ;; rm == {010b} --> (br 2)[Involves BP]
                          3 ;; rm == {011b} --> (br 3)[Involves BP]
                          4 ;; rm == {100b} --> (br 4)
                          5 ;; rm == {101b} --> (br 5)
                          6 ;; rm == {110b} --> (br 6)[Involves BP]
                          7 ;; 000b > rm OR rm >= 111b --> (br 7 (Default))
                        ))
                      ;; R/M table 3 with 16-Bit displacement for (br 0)
                      (return (global.set $ea (call $ram.decode
                          (select (global.get $seg) (call $register.segment.get (global.get $DS))
                                  (global.get $seg_override))
                          (i32.add
                            (i32.add
                              (call $register.general.get16 (global.get $BX))
                              (call $register.general.get16 (global.get $SI))
                            )
                            (block (result i32)
                              (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
                              (call $step_ip (i32.const 2))
                            )
                          )
                        ))
                      ))
                    ;; R/M table 3 with 16-Bit displacement for (br 1)
                    (return (global.set $ea (call $ram.decode
                        (select (global.get $seg) (call $register.segment.get (global.get $DS))
                                (global.get $seg_override)
                        (i32.add
                          (i32.add
                            (call $register.general.get16 (global.get $BX))
                            (call $register.general.get16 (global.get $DI))
                          )
                          (block (result i32)
                            (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
                            (call $step_ip (i32.const 2))
                          )
                        ))
                      ))
                    ))
                  ;; R/M table 3 with 16-Bit displacement for (br 2)
                  (return (global.set $ea (call $ram.decode
                      (select (global.get $seg) (call $register.segment.get (global.get $SS))
                              (global.get $seg_override))
                      (i32.add
                        (i32.add
                          (call $register.general.get16 (global.get $BP))
                          (call $register.general.get16 (global.get $SI))
                        )
                        (block (result i32)
                          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
                          (call $step_ip (i32.const 2))
                        )
                      )
                    ))
                  ))
                ;; R/M table 3 with 16-Bit displacement (br 3)
                (return (global.set $ea (call $ram.decode
                    (select (global.get $seg) (call $register.segment.get (global.get $SS))
                            (global.get $seg_override))
                    (i32.add
                      (i32.add
                        (call $register.general.get16 (global.get $BP))
                        (call $register.general.get16 (global.get $DI))
                      )
                      (block (result i32)
                        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
                        (call $step_ip (i32.const 2))
                      )
                    )
                  ))
                ))
              ;; R/M table 3 with 16-Bit displacement for (br 4)
              (return (global.set $ea (call $ram.decode 
                  (select (global.get $seg) (call $register.segment.get (global.get $DS))
                          (global.get $seg_override))
                  (i32.add 
                    (call $register.general.get16 (global.get $SI))
                    (block (result i32)
                      (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
                      (call $step_ip (i32.const 2))
                    )
                  )
                ))
              ))
            ;; R/M table 3 with 16-Bit displacement for (br 5)
            (return (global.set $ea (call $ram.decode 
                (select (global.get $seg) (call $register.segment.get (global.get $DS))
                        (global.get $seg_override))
                (i32.add 
                  (call $register.general.get16 (global.get $DI))
                  (block (result i32)
                    (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
                    (call $step_ip (i32.const 2))
                  )
                )
              ))
            ))
          ;; R/M table 3 with 16-Bit displacement for (br 6)
          (return (global.set $ea (call $ram.decode 
              (select (global.get $seg) (call $register.segment.get (global.get $SS))
                      (global.get $seg_override))
              (i32.add 
                (call $register.general.get16 (global.get $BP))
                (block (result i32)
                  (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
                  (call $step_ip (i32.const 2))
                )
              )
            ))
          ))
        ;; (default) R/M table 3 with 16-Bit displacement for (br 7)
        (return (global.set $ea (call $ram.decode 
            (select (global.get $seg) (call $register.segment.get (global.get $DS))
                    (global.get $seg_override))
            (i32.add 
              (call $register.general.get16 (global.get $BX))
              (block (result i32)
                (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
                (call $step_ip (i32.const 2))
              )
            )
          ))
        ))
      (; R/M table 3 with 16-Bit displacement ;)
    ;; (Default) Mod target for (br 3)
    (return) ;; If mod equals 11b then there is no meaningful need for $compute_ea to run, so it simply returns.
  )

  ;; 8086 OpCode lengths can vary from 1 (No operands) to 6.
  ;; Be aware that the Mod|Reg|R/M field may not be present even if 
  ;; the opcode has a length higher than 1, some Hardwired OpCodes such
  ;; as 0x04 (ADD AL, Ib) are an example of this.
  ;;
  ;; 8086 Instruction format:
  ;; 
  ;; Byte\Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
  ;; ---------|-----------------------|---|---|-
  ;;     1    |         opcode        | d | w | Opcode byte
  ;;     2    |  mod  |    reg    |    r/m    | Addressing mode byte
  ;;     3    |           [optional]          | low disp, addr, or data
  ;;     4    |           [optional]          | high disp, addr, or data
  ;;     5    |           [optional]          | low data
  ;;     6    |           [optional]          | high data
  ;;
  ;; (http://aturing.umcs.maine.edu/~meadow/courses/cos335/8086-instformat.pdf)
  ;;
  ;; Registers that have a length higher than 1 _may_ be followed by a Mod|Reg|R/M Byte.
  ;; The said byte should provide us with sufficient info to decide what kind of operation
  ;; we are dealing with, and to compute an Effective Address if required.
  ;;
  ;; This function will extract individual fields from that byte.  Handling the creation
  ;; of our Effective Address is done inside of $compute_ea.
  (func $parse_address (local $address i32)
    (local.set $address
      (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
    )
    (call $step_ip (i32.const 1)) ;; $IP has to be incremented by 1 after fetching the byte containg Mod|Reg|R/M.

    ;; The following fields will extract Mod, Reg and R/M from the previously fetched byte.
    (global.set $rm
      (i32.and (local.get $address) (i32.const 7)) ;; Bits 0, 1 and 2; simply performing bit-wise AND will result in rm's value.
    )
    (global.set $reg 
      (i32.and ;; Performing AND after masking will provide us with reg's value.
        (i32.shr_u (local.get $address) (i32.const 3)) ;; Bits 3 to 5; This line will mask off the lower bits.
        (i32.const 7)
      )
    )
    (global.set $mod
      (i32.shr_u (local.get $address) (i32.const 6)) ;; Most significant bits; only requires masking the lower bits, without any AND's.
    )

    call $compute_ea
  )


  ;; Sets Zero/Sign/Parity flags accordingly to the resulting value from math operations, does not 'Consume' the value.
  (func $set_zsp (param $mode i32) (param $value i32)
                 (result i32)
    ;; If the value equals 0 then ZF is set to 1; 0 otherwise.
    (call $register.flag.set
      (global.get $ZF)
      (call $i32.not (local.get $value))
    )

    ;; If the high-order bit of the value is a 1 then SF is set to 1; 0 otherwise. (Two's complement notation)
    (call $register.flag.set
      (global.get $SF)
      (i32.shr_u
        (local.get $value)
        (select (i32.const 15) (i32.const 7) 
                (local.get $mode))
      )
    )

    ;; If the value has even parity (an even number of 1-Bits) PF is set to 1; 0 otherwise.
    (call $register.flag.set
      (global.get $PF)
      (call $i32.not
        (i32.rem_u
          (i32.popcnt (local.get $value))
          (i32.const 2)
        )
      )
    )

    (return (local.get $value))
  )
  
  ;; Sets Adjust/Overflow/Carry flags just like above.
  ;; $operation indicates whether the operation is a subtraction (1) or an addition (0).
  ;; $mode states a 16-Bit operation (1) or 8-Bit (0).
  (func $set_aco (param $mode i32) (param $operation i32) (param $destination i32) (param $source i32)
                 (local $result i32)
    (select (call $i32.neg (local.get $source)) (local.get $source)
            (local.get $operation))
    local.set $source
    ;; The result from addition/subtraction has to be calculated locally to properly detect things like overflowing.
    (i32.add (local.get $destination) (local.get $source))
    local.set $result

    ;; Auxiliary Flag is like CF, but used when working with binary-coded decimals (BCD).
    (call $register.flag.set
      (global.get $AF)
      (select (i32.and (i32.xor (i32.xor (local.get $destination) (call $i32.neg (local.get $source))) (local.get $result)) (i32.const 16))
                (i32.eq
                  (i32.and (i32.xor (i32.xor (local.get $destination) (local.get $source)) (local.get $result)) (i32.const 16))
                  (i32.const 16)
                )
              (local.get $operation))
    )

    ;; If the result of an arithmetic operation equals or is larger than (2 ^ 16/8) OR the subtrahend is larger than minuend, CF is set to 1; 0 otherwise.
    (call $register.flag.set
      (global.get $CF)
      (select (i32.const 1) (select (i32.gt_u (call $i32.neg (local.get $source)) (local.get $destination)) (i32.const 0)                          
                                    (local.get $operation))
              (i32.ge_u (local.get $result) (select (i32.const 65536) (i32.const 256) 
                                                    (local.get $mode))))
    )
    
    ;; If the result of a signed operation is too large to be represented in 7 or 15 bits (depending on $mode), Then OF is set to 1; 0 otherwise.
    ;; http://teaching.idallen.com/dat2343/10f/notes/040_overflow.txt explains Carry & Overflow flags in a very detailed manner.
    ;; Summarizing, overflow only occurs if both operands have the same sign and it differs from the result's sign.
    (call $register.flag.set
      (global.get $OF)
      (call $i32.not
        (i32.rem_u ;; This will separate even's (Overflow) from odds.  The outcome has to be negated.
          (i32.popcnt ;; Both 0 (00b) and 3 (11b) will have an even number of 1-Bits, unlike 1 (01b) and 2 (10b).
            (i32.add ;; Incrementing by 1 will ensure that Two's complement (For -1) will not interfere with population counting.
              (i32.sub ;; If the result equals -1 or 2, then an overflow happend.
                (i32.add ;; If the result is 2 both values were Negative; if it is 0 then both were Positive; otherwise only one of them was.
                  (i32.shr_u (local.get $destination) (i32.const 15))
                  (i32.shr_u (local.get $source) (i32.const 15))
                )
                (select (i32.const 1) (i32.const 0)
                        (i32.shr_s 
                          (i32.shl (local.get $result) (select (i32.const 16) (i32.const 24)
                                                               (local.get $mode)))
                          (i32.const 31)
                        )) ;; Could also use Sign Flag's value, if $set_zsp is guaranteed to be called beforehand.
              )
              (i32.const 1)
            )
          )
        (i32.const 2)
        )
      )
    )
  )


  (; OpCode backends (Commonly used assets across OpCodes) ;)
  ;; a sign-agnostic Binary operation with multiple conditions that adds a value (plus an optional carry flag) to another.
  ;; As for subtraction, Although it is a "real" instruction at the hardware level (i.e., SUB has it's own binary OpCode and the 
  ;; CPU itself will be aware that it should produce result of subtraction), we can reuse the existing $checked_add function;
  ;; since we are _emulating_ a 8086, we had to take a completely different approach if we were to _simulate_ that CPU.
  ;;
  ;; $operation indicates whether the operation is a subtraction (1) or an addition (0).
  ;; $mode states a 16-Bit operation (1) or 8-Bit (0).
  (func $checked_add (param $mode i32) (param $operation i32) (param $carry i32) (param $destination i32) (param $source i32)
                     (result i32)
    local.get $mode ;; Pushes the first parameter of $set_zsp onto the stack.

    (i32.and ;; This will discard the bits higher than 8/16 (Depending on $mode).
      (i32.add
        (i32.add (local.get $destination) (select (call $i32.neg (local.get $source)) (local.get $source)
                                                  (local.get $operation)))
        (select (select (call $i32.neg (call $register.flag.get (global.get $CF))) (call $register.flag.get (global.get $CF))
                        (local.get $operation)) (i32.const 0)
                (local.get $carry))
      )
      (select (i32.const 65535) (i32.const 255) 
              (local.get $mode)) ;; We could also use our i16.add or i8.add functions but that would sacrifice legibility or runtime performance.
    )
    
    call $set_zsp
    (call $set_aco (local.get $mode) (local.get $operation ) (local.get $destination) (local.get $source))

    return (; value that is left on the stack ;)
  )

  ;; Conditionally jumps ahead (or backwards) in the code.
  (func $jump (param $condition i32) (param $amount i32)
    (call $step_ip
      (select (local.get $amount) (i32.const 0)
              (local.get $condition))
    )
  )

  ;; This will convert all flag registers (Including the reserved bits) into a single word (16-Bit).
  ;; Refer to the comments above the $registers array for more information about these values.
  ;; Bitwise concatenation is done using left shift (<<), similar to how segments are encoded/decoded.
  ;; This could also be done using a 'for' loop.
  (func $u16.convert_flags (result i32)
    (return
      (i32.and 
        (i32.or (i32.or (i32.or (i32.or (i32.or (i32.or (i32.or (i32.or
          (i32.or (i32.or (i32.or (i32.or (i32.or (i32.or (i32.or
            (i32.shl (call $register.flag.get (global.get $CF)) (i32.const 0)) ;; CF

            (i32.shl (call $register.flag.get (i32.const 1)) (i32.const 1)) ;; UD
          )
            (i32.shl (call $register.flag.get (global.get $PF)) (i32.const 2)) ;; PF
          )
            (i32.shl (call $register.flag.get (i32.const 3)) (i32.const 3)) ;; UD
          )
            (i32.shl (call $register.flag.get (global.get $AF)) (i32.const 4)) ;; AF
          )
            (i32.shl (call $register.flag.get (i32.const 5)) (i32.const 5)) ;; UD
          )
            (i32.shl (call $register.flag.get (global.get $ZF)) (i32.const 6)) ;; ZF
          )
            (i32.shl (call $register.flag.get (global.get $SF)) (i32.const 7)) ;; SF
          )
            (i32.shl (call $register.flag.get (global.get $TF)) (i32.const 8)) ;; TF
          )
            (i32.shl (call $register.flag.get (global.get $IF)) (i32.const 9)) ;; IF
          )
            (i32.shl (call $register.flag.get (global.get $DF)) (i32.const 10)) ;; DF
          )
            (i32.shl (call $register.flag.get (global.get $OF)) (i32.const 11)) ;; OF
          )
            (i32.shl (call $register.flag.get (i32.const 12)) (i32.const 12)) ;; UD
          )
            (i32.shl (call $register.flag.get (i32.const 13)) (i32.const 13)) ;; UD
          )
            (i32.shl (call $register.flag.get (i32.const 14)) (i32.const 14)) ;; UD
          )
            (i32.shl (call $register.flag.get (i32.const 16)) (i32.const 16)) ;; UD
          )
          (i32.const 65535) ;; 16-Bit integer casting.
      )
    )
  )
  ;; This does the exact opposite of above, accepts a value and distributes it among all flag registers.
  ;; It extracts individual bits using masking and bitwise ands.
  (func $flag.convert_u16 (param $value i32)
    ;; CF
    (call $register.flag.set (global.get $CF) (i32.and (i32.shr_u (local.get $value) (i32.const 0)) (i32.const 1)))

    ;; UD
    (call $register.flag.set (i32.const 1) (i32.and (i32.shr_u (local.get $value) (i32.const 1)) (i32.const 1)))

    ;; PF
    (call $register.flag.set (global.get $PF) (i32.and (i32.shr_u (local.get $value) (i32.const 2)) (i32.const 1)))

    ;; UD
    (call $register.flag.set (i32.const 3) (i32.and (i32.shr_u (local.get $value) (i32.const 3)) (i32.const 1)))

    ;; AF
    (call $register.flag.set (global.get $AF) (i32.and (i32.shr_u (local.get $value) (i32.const 4)) (i32.const 1)))

    ;; UD
    (call $register.flag.set (i32.const 5) (i32.and (i32.shr_u (local.get $value) (i32.const 5)) (i32.const 1)))

    ;; ZF
    (call $register.flag.set (global.get $ZF) (i32.and (i32.shr_u (local.get $value) (i32.const 6)) (i32.const 1)))

    ;; SF
    (call $register.flag.set (global.get $SF) (i32.and (i32.shr_u (local.get $value) (i32.const 7)) (i32.const 1)))

    ;; TF
    (call $register.flag.set (global.get $TF) (i32.and (i32.shr_u (local.get $value) (i32.const 8)) (i32.const 1)))

    ;; IF
    (call $register.flag.set (global.get $IF) (i32.and (i32.shr_u (local.get $value) (i32.const 9)) (i32.const 1)))

    ;; DF
    (call $register.flag.set (global.get $CF) (i32.and (i32.shr_u (local.get $value) (i32.const 10)) (i32.const 1)))

    ;; OF
    (call $register.flag.set (global.get $CF) (i32.and (i32.shr_u (local.get $value) (i32.const 11)) (i32.const 1)))

    ;; UD
    (call $register.flag.set (i32.const 12) (i32.and (i32.shr_u (local.get $value) (i32.const 12)) (i32.const 1)))

    ;; UD
    (call $register.flag.set (i32.const 13) (i32.and (i32.shr_u (local.get $value) (i32.const 13)) (i32.const 1)))

    ;; UD
    (call $register.flag.set (i32.const 14) (i32.and (i32.shr_u (local.get $value) (i32.const 14)) (i32.const 1)))

    ;; UD
    (call $register.flag.set (i32.const 15) (i32.and (i32.shr_u (local.get $value) (i32.const 15)) (i32.const 1)))
  )


  (; OpCodes (http://www.mlsite.net/8086/) ;)
  (func $0x00 (; ADD Eb, Gb ;)
    call $parse_address

    (call $logical_write8
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
  )
  (func $0x01 (; ADD Ev, Gv ;) 
    call $parse_address

    (call $logical_write16
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
  )
  (func $0x02 (; ADD Gb, Eb ;) 
    call $parse_address

    (call $register.general.set8
      (global.get $reg)
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $reg))
        (call $logical_read8)
      )
    )
  )
  (func $0x03 (; ADD Gv, Ev ;)
    call $parse_address

    (call $register.general.set16
      (global.get $reg)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get16 (global.get $reg))
        (call $logical_read16)
      )
    )
  )
  (func $0x04 (; ADD AL, Ib;)
    (call $register.general.set8
      (global.get $AL)
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $AL))
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x05 (; ADD AX, Iv ;) 
    (call $register.general.set16
      (global.get $AX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get16 (global.get $AX))
        (block (result i32)
          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 2))
        )
      )
    )
  )
  
  (func $0x06 (; PUSH ES ;)
    (call $push
      (call $register.segment.get (global.get $ES))
    )
  )
  (func $0x07 (; POP ES ;)
    (call $register.segment.set 
      (global.get $ES)
      (call $pop)
    )
  )

  (func $0x08 (; OR Eb, Gb ;)
    call $parse_address

    (call $logical_write8
      (i32.or
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
  )
  (func $0x09 (; OR Ev, Gv ;)
    call $parse_address

    (call $logical_write16
      (i32.or
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
  )
  (func $0x0a (; OR Gb, Eb ;)
    call $parse_address

    (call $register.general.set8
      (global.get $reg)
      (i32.or
        (call $register.general.get8 (global.get $reg))
        (call $logical_read8)
      )
    )
  )
  (func $0x0b (; OR Gv, Ev ;)
    call $parse_address

    (call $register.general.set16
      (global.get $reg)
      (i32.or
        (call $register.general.get16 (global.get $reg))
        (call $logical_read16)
      )
    )
  )
  (func $0x0c (; OR AL, Ib ;)
    (call $register.general.set8
      (global.get $AL)
      (i32.or
        (call $register.general.get8 (global.get $AL))
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x0d (; OR AX, Iv;)
    (call $register.general.set16
      (global.get $AX)
      (i32.or
        (call $register.general.get8 (global.get $AX))
        (block (result i32)
          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 2))
        )
      )
    )
  )

  (func $0x0e (; PUSH CS ;)
    (call $push
      (call $register.segment.get (global.get $CS))
    )
  )

  (func $0x10 (; ADC Eb, Gb ;)
    call $parse_address

    (call $logical_write8
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 0) ;; Addition
        (i32.const 1) ;; Carry
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
  )
  (func $0x11 (; ADC Ev, Gv ;) 
    call $parse_address

    (call $logical_write16
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 1) ;; Carry
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
  )
  (func $0x12 (; ADC Gb, Eb ;) 
    call $parse_address

    (call $register.general.set8
      (global.get $reg)
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 0) ;; Addition
        (i32.const 1) ;; Carry
        (call $register.general.get8 (global.get $reg))
        (call $logical_read8)
      )
    )
  )
  (func $0x13 (; ADC Gv, Ev ;)
    call $parse_address

    (call $register.general.set16
      (global.get $reg)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 1) ;; Carry
        (call $register.general.get16 (global.get $reg))
        (call $logical_read16)
      )
    )
  )
  (func $0x14 (; ADC AL, Ib;)
    (call $register.general.set8
      (global.get $AL)
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 0) ;; Addition
        (i32.const 1) ;; Carry
        (call $register.general.get8 (global.get $AL))
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x15 (; ADC AX, Iv ;) 
    (call $register.general.set16
      (global.get $AX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 1) ;; Carry
        (call $register.general.get16 (global.get $AX))
        (block (result i32)
          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 2))
        )
      )
    )
  )

  (func $0x16 (; PUSH SS ;)
    (call $push
      (call $register.segment.get (global.get $SS))
    )
  )
  (func $0x17 (; POP SS ;)
    (call $register.segment.set 
      (global.get $SS)
      (call $pop)
    )
  )

  (func $0x18 (; SBB Eb, Gb ;)
    call $parse_address

    (call $logical_write8
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 1) ;; Carry
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
  )
  (func $0x19 (; SBB Ev, Gv ;) 
    call $parse_address

    (call $logical_write16
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 1) ;; Carry
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
  )
  (func $0x1a (; SBB Gb, Eb ;) 
    call $parse_address

    (call $register.general.set8
      (global.get $reg)
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 1) ;; Carry
        (call $register.general.get8 (global.get $reg))
        (call $logical_read8)
      )
    )
  )
  (func $0x1b (; SBB Gv, Ev ;)
    call $parse_address

    (call $register.general.set16
      (global.get $reg)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 1) ;; Carry
        (call $register.general.get16 (global.get $reg))
        (call $logical_read16)
      )
    )
  )
  (func $0x1c (; SBB AL, Ib;)
    (call $register.general.set8
      (global.get $AL)
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 1) ;; Carry
        (call $register.general.get8 (global.get $AL))
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x1d (; SBB AX, Iv ;) 
    (call $register.general.set16
      (global.get $AX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 1) ;; Carry
        (call $register.general.get16 (global.get $AX))
        (block (result i32)
          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 2))
        )
      )
    )
  )

  (func $0x1e (; PUSH DS ;)
    (call $push
      (call $register.segment.get (global.get $DS))
    )
  )
  (func $0x1f (; POP DS ;)
    (call $register.segment.set 
      (global.get $DS)
      (call $pop)
    )
  )

  (func $0x20 (; AND Eb, Gb ;)
    call $parse_address

    (call $logical_write8
      (i32.and
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
  )
  (func $0x21 (; AND Ev, Gv ;)
    call $parse_address

    (call $logical_write16
      (i32.and
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
  )
  (func $0x22 (; AND Gb, Eb ;)
    call $parse_address

    (call $register.general.set8
      (global.get $reg)
      (i32.and
        (call $register.general.get8 (global.get $reg))
        (call $logical_read8)
      )
    )
  )
  (func $0x23 (; AND Gv, Ev ;)
    call $parse_address

    (call $register.general.set16
      (global.get $reg)
      (i32.and
        (call $register.general.get16 (global.get $reg))
        (call $logical_read16)
      )
    )
  )
  (func $0x24 (; AND AL, Ib ;)
    (call $register.general.set8
      (global.get $AL)
      (i32.and
        (call $register.general.get8 (global.get $AL))
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x25 (; AND AX, Iv;)
    (call $register.general.set16
      (global.get $AX)
      (i32.and
        (call $register.general.get8 (global.get $AX))
        (block (result i32)
          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 2))
        )
      )
    )
  )

  (func $0x26 (; ES: ;)
    (global.set $seg
      (call $register.segment.get (global.get $ES))
    )
    (global.set $seg_override (i32.const 1))

    call $execute

    (global.set $seg (call $register.segment.get (global.get $DS)))
    (global.set $seg_override (i32.const 0))
  )

  ;; https://www.gabrielececchetti.it/Teaching/CalcolatoriElettronici/Docs/i8086_instruction_set.pdf
  ;; https://www.felixcloutier.com/x86/daa
  (func $0x27 (; DAA ;)
    (if 
      (i32.or
        (i32.ge_u
          (i32.and (call $register.general.get8 (global.get $AL)) (i32.const 0xf))
          (i32.const 9)
        )
        (call $register.flag.get (global.get $AF))
      )
      (then
        (call $register.general.set8
          (global.get $AL)
          (i32.add
            (call $register.general.get8 (global.get $AL))
            (i32.const 6)
          )
        )

        (call $register.flag.set
          (global.get $CF)
          (select (i32.const 1) (i32.const 0)
                  (i32.gt_u (call $register.general.get8 (global.get $AL)) (i32.const 0xff)))
        )

        (call $register.flag.set
          (global.get $AF)
          (i32.const 1)
        )
      )
      (else
        (call $register.flag.set
          (global.get $AF)
          (i32.const 0)
        )
      )
    )

    (if
      (i32.or
        (i32.ge_u (call $register.general.get8 (global.get $AL)) (i32.const 0x9f))
        (call $register.flag.get (global.get $CF))
      )
      (then
        (call $register.general.set8
          (global.get $AL)
          (i32.add
            (call $register.general.get8 (global.get $AL))
            (i32.const 0x60)
          )

          (call $register.flag.set
            (global.get $CF)
            (i32.const 1)
          )
        )
      )
      (else
        (call $register.flag.set
          (global.get $CF)
          (i32.const 0)
        )
      )
    )
  )
  
  (func $0x28 (; SUB Eb, Gb ;)
    call $parse_address

    (call $logical_write8
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
  )
  (func $0x29 (; SUB Ev, Gv ;) 
    call $parse_address

    (call $logical_write16
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
  )
  (func $0x2a (; SUB Gb, Eb ;) 
    call $parse_address

    (call $register.general.set8
      (global.get $reg)
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $reg))
        (call $logical_read8)
      )
    )
  )
  (func $0x2b (; SUB Gv, Ev ;)
    call $parse_address

    (call $register.general.set16
      (global.get $reg)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get16 (global.get $reg))
        (call $logical_read16)
      )
    )
  )
  (func $0x2c (; SUB AL, Ib;)
    (call $register.general.set8
      (global.get $AL)
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $AL))
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x2d (; SUB AX, Iv ;) 
    (call $register.general.set16
      (global.get $AX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get16 (global.get $AX))
        (block (result i32)
          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 2))
        )
      )
    )
  )

  (func $0x2e (; CS: ;)
    (global.set $seg
      (call $register.segment.get (global.get $CS))
    )
    (global.set $seg_override (i32.const 1))

    call $execute

    (global.set $seg (call $register.segment.get (global.get $DS)))
    (global.set $seg_override (i32.const 0))
  )

  ;; https://www.gabrielececchetti.it/Teaching/CalcolatoriElettronici/Docs/i8086_instruction_set.pdf
  (func $0x2f (; DAS ;)
    (if 
      (i32.or
        (i32.ge_u
          (i32.and (call $register.general.get8 (global.get $AL)) (i32.const 0xf))
          (i32.const 9)
        )
        (call $register.flag.get (global.get $AF))
      )
      (then
        (call $register.general.set8
          (global.get $AL)
          (i32.sub
            (call $register.general.get8 (global.get $AL))
            (i32.const 6)
          )
        )

        (call $register.flag.set
          (global.get $CF)
          (select (i32.const 1) (i32.const 0)
                  (i32.gt_u (call $register.general.get8 (global.get $AL)) (i32.const 0xff)))
        )

        (call $register.flag.set
          (global.get $AF)
          (i32.const 1)
        )
      )
      (else
        (call $register.flag.set
          (global.get $AF)
          (i32.const 0)
        )
      )
    )

    (if
      (i32.or
        (i32.ge_u (call $register.general.get8 (global.get $AL)) (i32.const 0x9f))
        (call $register.flag.get (global.get $CF))
      )
      (then
        (call $register.general.set8
          (global.get $AL)
          (i32.sub
            (call $register.general.get8 (global.get $AL))
            (i32.const 0x60)
          )

          (call $register.flag.set
            (global.get $CF)
            (i32.const 1)
          )
        )
      )
      (else
        (call $register.flag.set
          (global.get $CF)
          (i32.const 0)
        )
      )
    )
  )

  (func $0x30 (; XOR Eb, Gb ;)
    call $parse_address

    (call $logical_write8
      (i32.xor
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
  )
  (func $0x31 (; XOR Ev, Gv ;)
    call $parse_address

    (call $logical_write16
      (i32.xor
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
  )
  (func $0x32 (; XOR Gb, Eb ;)
    call $parse_address

    (call $register.general.set8
      (global.get $reg)
      (i32.xor
        (call $register.general.get8 (global.get $reg))
        (call $logical_read8)
      )
    )
  )
  (func $0x33 (; XOR Gv, Ev ;)
    call $parse_address

    (call $register.general.set16
      (global.get $reg)
      (i32.xor
        (call $register.general.get16 (global.get $reg))
        (call $logical_read16)
      )
    )
  )
  (func $0x34 (; XOR AL, Ib ;)
    (call $register.general.set8
      (global.get $AL)
      (i32.xor
        (call $register.general.get8 (global.get $AL))
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x35 (; XOR AX, Iv;)
    (call $register.general.set16
      (global.get $AX)
      (i32.xor
        (call $register.general.get8 (global.get $AX))
        (block (result i32)
          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 2))
        )
      )
    )
  )

  (func $0x36 (; SS: ;)
    (global.set $seg
      (call $register.segment.get (global.get $SS))
    )
    (global.set $seg_override (i32.const 1))

    call $execute

    (global.set $seg (call $register.segment.get (global.get $DS)))
    (global.set $seg_override (i32.const 0))
  )

  ;; https://www.gabrielececchetti.it/Teaching/CalcolatoriElettronici/Docs/i8086_instruction_set.pdf
  (func $0x37 (; AAA ;)
    (if 
      (i32.or
        (i32.ge_u
          (i32.and (call $register.general.get8 (global.get $AL)) (i32.const 0xf))
          (i32.const 9)
        )
        (call $register.flag.get (global.get $AF))
      )
      (then
        (call $register.general.set8 
          (global.get $AL)
          (i32.add
            (call $register.general.get8 (global.get $AL))
            (i32.const 6)
          )
        )
        (call $register.general.set8 
          (global.get $AH)
          (i32.add
            (call $register.general.get8 (global.get $AH))
            (i32.const 1)
          )
        )

        (call $register.flag.set
          (global.get $AF)
          (i32.const 1)
        )
        (call $register.flag.set
          (global.get $CF)
          (i32.const 1)
        )
      )
      (else
        (call $register.flag.set
          (global.get $AF)
          (i32.const 0)
        )
        (call $register.flag.set
          (global.get $CF)
          (i32.const 0)
        )
      )
    )
  )

  (func $0x38 (; CMP Eb, Gb ;)
    call $parse_address

    (drop
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
  )
  (func $0x39 (; CMP Ev, Gv ;) 
    call $parse_address

    (drop
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
  )
  (func $0x3a (; CMP Gb, Eb ;) 
    call $parse_address

    (drop
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $reg))
        (call $logical_read8)
      )
    )
  )
  (func $0x3b (; CMP Gv, Ev ;)
    call $parse_address

    (call $register.general.set16
      (global.get $reg)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get16 (global.get $reg))
        (call $logical_read16)
      )
    )
  )
  (func $0x3c (; CMP AL, Ib;)
    (drop
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $AL))
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x3d (; CMP AX, Iv ;) 
    (drop
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get16 (global.get $AX))
        (block (result i32)
          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 2))
        )
      )
    )
  )

  (func $0x3e (; DS: ;)
    (global.set $seg
      (call $register.segment.get (global.get $DS))
    )
    (global.set $seg_override (i32.const 1))

    call $execute

    (global.set $seg (call $register.segment.get (global.get $DS)))
    (global.set $seg_override (i32.const 0))
  )

  ;; https://www.gabrielececchetti.it/Teaching/CalcolatoriElettronici/Docs/i8086_instruction_set.pdf
  (func $0x3f (; AAS ;)
    (if 
      (i32.or
        (i32.ge_u
          (i32.and (call $register.general.get8 (global.get $AL)) (i32.const 0xf))
          (i32.const 9)
        )
        (call $register.flag.get (global.get $AF))
      )
      (then
        (call $register.general.set8 
          (global.get $AL)
          (i32.sub
            (call $register.general.get8 (global.get $AL))
            (i32.const 6)
          )
        )
        (call $register.general.set8 
          (global.get $AH)
          (i32.sub
            (call $register.general.get8 (global.get $AH))
            (i32.const 1)
          )
        )

        (call $register.flag.set
          (global.get $AF)
          (i32.const 1)
        )
        (call $register.flag.set
          (global.get $CF)
          (i32.const 1)
        )
      )
      (else
        (call $register.flag.set
          (global.get $AF)
          (i32.const 0)
        )
        (call $register.flag.set
          (global.get $CF)
          (i32.const 0)
        )
      )
    )
  )

  (func $0x40 (; INC AX ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $AX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $AX))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x41 (; INC CX ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $CX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $CX))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x42 (; INC DX ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $DX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $DX))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x43 (; INC BX ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $BX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $BX))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x44 (; INC SP ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $SP)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $SP))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x45 (; INC BP ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $BP)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $BP))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x46 (; INC SI ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $SI)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $SI))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x47 (; INC DI ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $DI)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 0) ;; Addition
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $DI))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )  

  (func $0x48 (; DEC AX ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $AX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $AX))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x49 (; DEC CX ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $CX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $CX))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x4a (; DEC DX ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $DX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $DX))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x4b (; DEC BX ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $BX)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $BX))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x4c (; DEC SP ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $SP)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $SP))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x4d (; DEC BP ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $BP)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $BP))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x4e (; DEC SI ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $SI)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $SI))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0x4f (; DEC DI ;)
    global.get $CF
    call $register.flag.get

    (call $register.general.set16 
      (global.get $DI)
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $DI))
        (i32.const 1)
      )
    )

    global.get $CF
    call $register.flag.set
  )
  
  (func $0x50 (; PUSH AX ;)
    (call $push
      (call $register.general.get16 (global.get $AX))
    )
  )
  (func $0x51 (; PUSH CX ;)
    (call $push
      (call $register.general.get16 (global.get $CX))
    )
  )
  (func $0x52 (; PUSH DX ;)
    (call $push
      (call $register.general.get16 (global.get $DX))
    )
  )
  (func $0x53 (; PUSH BX ;)
    (call $push
      (call $register.general.get16 (global.get $BX))
    )
  )
  (func $0x54 (; PUSH SP ;)
    (call $push
      (call $register.general.get16 (global.get $SP))
    )
  )
  (func $0x55 (; PUSH BP ;)
    (call $push 
      (call $register.general.get16 (global.get $BP))
    )
  )
  (func $0x56 (; PUSH SI ;)
    (call $push
      (call $register.general.get16 (global.get $SI))
    )
  )
  (func $0x57 (; PUSH DI ;)
    (call $push
      (call $register.general.get16 (global.get $DI))
    )
  )

  (func $0x58 (; POP AX ;)
    (call $register.general.set16
      (global.get $AX)
      (call $pop)
    )
  )
  (func $0x59 (; POP CX ;)
    (call $register.general.set16
      (global.get $CX)
      (call $pop)
    )
  )
  (func $0x5a (; POP DX ;)
    (call $register.general.set16
      (global.get $DX)
      (call $pop)
    )
  )
  (func $0x5b (; POP BX ;)
    (call $register.general.set16
      (global.get $BX)
      (call $pop)
    )
  )
  (func $0x5c (; POP SP ;)
    (call $register.segment.set 
      (global.get $SP)
      (call $pop)
    )
  )
  (func $0x5d (; POP BP ;)
    (call $register.segment.set 
      (global.get $BP)
      (call $pop)
    )
  )
  (func $0x5e (; POP SI ;)
    (call $register.segment.set 
      (global.get $SI)
      (call $pop)
    )
  )
  (func $0x5f (; POP DI ;)
    (call $register.segment.set 
      (global.get $DI)
      (call $pop)
    )
  )

  (func $0x70 (; JO Jb ;)
    (call $jump 
      (call $register.flag.get (global.get $OF))
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x71 (; JNO Jb ;)
    (call $jump 
      (call $i32.not (call $register.flag.get (global.get $OF)))
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x72 (; JB Jb ;)
    (call $jump 
      (call $register.flag.get (global.get $CF))
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x73 (; JNB Jb ;)
    (call $jump 
      (call $i32.not (call $register.flag.get (global.get $CF)))
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x74 (; JZ Jb ;)
    (call $jump 
      (call $register.flag.get (global.get $ZF))
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x75 (; JNZ Jb ;)
    (call $jump 
      (call $i32.not (call $register.flag.get (global.get $ZF)))
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x76 (; JBE Jb ;)
    (call $jump 
      (i32.or
        (call $register.flag.get (global.get $CF))
        (call $register.flag.get (global.get $ZF))
      )
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x77 (; JA Jb ;)
    (call $jump 
      (i32.and
        (i32.eqz (call $register.flag.get (global.get $CF)))
        (i32.eqz (call $register.flag.get (global.get $ZF)))
      )
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x78 (; JS Jb ;)
    (call $jump 
      (call $register.flag.get (global.get $SF))
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0x79 (; JNS Jb ;)
    (call $jump 
      (call $i32.not (call $register.flag.get (global.get $SF)))
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x7a (; JPE Jb ;)
    (call $jump 
      (call $register.flag.get (global.get $PF))
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0x7b (; JPO Jb ;)
    (call $jump 
      (call $i32.not (call $register.flag.get (global.get $PF)))
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x7c (; JL Jb ;)
    (call $jump 
      (i32.xor
        (call $register.flag.get (global.get $SF))
        (call $register.flag.get (global.get $OF))
      )
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x7d (; JGE Jb ;)
    (call $jump 
      (i32.eq ;; WebAssembly does not have 'i32.xnor'.
        (call $register.flag.get (global.get $SF))
        (call $register.flag.get (global.get $OF))
      )
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x7e (; JLE Jb ;)
    (call $jump 
      (i32.or
        (i32.xor
          (call $register.flag.get (global.get $SF))
          (call $register.flag.get (global.get $OF))
        )
        (i32.eq (call $register.flag.get (global.get $OF)) (i32.const 1))
      )
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0x7f (; JG Jb ;)
    (call $jump 
      (i32.and
        (i32.eqz (call $register.flag.get (global.get $ZF)))
        (i32.eqz (call $register.flag.get (global.get $OF)))
      )
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )

  (func $0x80 (; GRP1 Eb, Ib ;)
    call $parse_address
    
    (call $GRP1/8
      (call $logical_read8)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0x81 (; GRP1 Ev, Iv ;)
    call $parse_address
    
    (call $GRP1/16
      (call $logical_read16)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )
  (func $0x82 (; GRP1 Eb, Ib ;)
    call $parse_address
    
    (call $GRP1/8
      (call $logical_read8)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0x83 (; GRP1 Ev, Ib ;)
    call $parse_address
    
    (call $GRP1/16
      (call $logical_read16)
      (call $i16.extend8_s ;; This OpCode accepts both a byte AND a word as it's operands, so the byte has to be sign-extended.
        (block (result i32)
          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 2))
        )
      )
    )
  )

  (func $0x84 (; TEST Gb, Eb ;)
    call $parse_address

    (drop
      (call $set_zsp
        (i32.const 0)
        (i32.and
          (call $logical_read8)
          (call $register.general.get8 (global.get $reg))
        )
      )
    )
  )
  (func $0x85 (; TEST Gv, Ev ;)
    call $parse_address

    (drop
      (call $set_zsp
        (i32.const 1)
        (i32.and
          (call $logical_read16)
          (call $register.general.get16 (global.get $reg))
        )
      )
    )
  )

  ;; https://stackoverflow.com/questions/41957898/how-is-xchg-implemented-in-a-8086-processor
  (func $0x86 (; XCHG Gb, Eb ;)
    call $parse_address

    (call $logical_write8
      (i32.xor
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
    (call $register.general.set8
      (global.get $reg)
      (i32.xor
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
    (call $logical_write8
      (i32.xor
        (call $logical_read8)
        (call $register.general.get8 (global.get $reg))
      )
    )
  )
  (func $0x87 (; XCHG Gv, Ev ;)
    call $parse_address

    (call $logical_write16
      (i32.xor
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
    (call $register.general.set16
      (global.get $reg)
      (i32.xor
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
    (call $logical_write16
      (i32.xor
        (call $logical_read16)
        (call $register.general.get16 (global.get $reg))
      )
    )
  )

  (func $0x88 (; MOV Eb, Gb ;)
    call $parse_address

    (call $logical_write8
      (call $register.general.get8 (global.get $reg))
    )
  )
  (func $0x89 (; MOV Ev, Gv ;) 
    call $parse_address

    (call $logical_write16
      (call $register.general.get16 (global.get $reg))
    )
  )
  (func $0x8a (; MOV Gb, Eb ;) 
    call $parse_address

    (call $register.general.set8
      (global.get $reg)
      (call $logical_read8)
    )
  )
  (func $0x8b (; MOV Gv, Ev ;)
    call $parse_address

    (call $register.general.set16
      (global.get $reg)
      (call $logical_read16)
    )
  )
  (func $0x8c (; MOV Ew, Sw ;)
    call $parse_address

    (call $logical_write16
      (call $register.segment.get (global.get $reg))
    )
  )
  ;; https://www.felixcloutier.com/x86/lea
  (func $0x8d (; LEA Gv, M ;) 
    call $parse_address

    (call $register.general.set16
      (global.get $reg)
      (global.get $ea)
    )
  )
  (func $0x8e (; MOV Sw, Ew ;)
    call $parse_address

    (call $register.segment.set
      (global.get $reg)
      (call $logical_read16)
    )
  )

  (func $0x8f (; POP Ev ;)
    call $parse_address

    (call $logical_write16
      (call $pop)
    )
  )
  
  (func $0x90 (; NOP ;)
    nop
  )

  (func $0x91 (; XCHG CX, AX ;)
    (call $register.general.set16
      (global.get $CX)
      (i32.xor
        (call $register.general.get16 (global.get $CX))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $AX)
      (i32.xor
        (call $register.general.get16 (global.get $CX))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $CX)
      (i32.xor
        (call $register.general.get16 (global.get $CX))
        (call $register.general.get16 (global.get $AX))
      )
    )
  )
  (func $0x92 (; XCHG DX, AX ;)
    (call $register.general.set16
      (global.get $DX)
      (i32.xor
        (call $register.general.get16 (global.get $DX))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $AX)
      (i32.xor
        (call $register.general.get16 (global.get $DX))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $DX)
      (i32.xor
        (call $register.general.get16 (global.get $DX))
        (call $register.general.get16 (global.get $AX))
      )
    )
  )
  (func $0x93 (; XCHG BX, AX ;)
    (call $register.general.set16
      (global.get $BX)
      (i32.xor
        (call $register.general.get16 (global.get $BX))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $AX)
      (i32.xor
        (call $register.general.get16 (global.get $BX))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $BX)
      (i32.xor
        (call $register.general.get16 (global.get $BX))
        (call $register.general.get16 (global.get $AX))
      )
    )
  )
  (func $0x94 (; XCHG SP, AX ;)
    (call $register.segment.set
      (global.get $SP)
      (i32.xor
        (call $register.segment.get (global.get $SP))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $AX)
      (i32.xor
        (call $register.segment.get (global.get $SP))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $SP)
      (i32.xor
        (call $register.segment.get (global.get $SP))
        (call $register.general.get16 (global.get $AX))
      )
    )
  )
  (func $0x95 (; XCHG BP, AX ;)
    (call $register.segment.set
      (global.get $BP)
      (i32.xor
        (call $register.segment.get (global.get $BP))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $AX)
      (i32.xor
        (call $register.segment.get (global.get $BP))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $BP)
      (i32.xor
        (call $register.segment.get (global.get $BP))
        (call $register.general.get16 (global.get $AX))
      )
    )
  )
  (func $0x96 (; XCHG SI, AX ;)
    (call $register.segment.set
      (global.get $SI)
      (i32.xor
        (call $register.segment.get (global.get $SI))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $AX)
      (i32.xor
        (call $register.segment.get (global.get $SI))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $SI)
      (i32.xor
        (call $register.segment.get (global.get $SI))
        (call $register.general.get16 (global.get $AX))
      )
    )
  )
  (func $0x97 (; XCHG DI, AX ;)
    (call $register.segment.set
      (global.get $DI)
      (i32.xor
        (call $register.segment.get (global.get $DI))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $AX)
      (i32.xor
        (call $register.segment.get (global.get $DI))
        (call $register.general.get16 (global.get $AX))
      )
    )
    (call $register.general.set16
      (global.get $DI)
      (i32.xor
        (call $register.segment.get (global.get $DI))
        (call $register.general.get16 (global.get $AX))
      )
    )
  )

  (func $0x98 (; CBW ;)
    (call $register.general.set8
      (global.get $AH)
      (select (i32.const 0xff) (i32.const 0x00)
              (i32.shr_u (call $register.general.get8 (global.get $AL)) (i32.const 7)))
    )
  )
  (func $0x99 (; CWD ;)
    (call $register.general.set16
      (global.get $DX)
      (select (i32.const 0xffff) (i32.const 0x0000)
              (i32.shr_u (call $register.general.get16 (global.get $AX)) (i32.const 15)))
    )
  )
  
  ;; this is a far call, so CS and IP are also pushed on to the stack (https://c9x.me/x86/html/file_module_x86_id_26.html).
  (func $0x9a (; CALL Ap ;)
    (block (result i32)
      (call $ram.read16 (call $register.segment.get (global.get $CS) (global.get $IP)))
      (call $step_ip (i32.const 2))
    )

    (block (result i32)
      (call $ram.read16 (call $register.segment.get (global.get $CS) (global.get $IP)))
      (call $step_ip (i32.const 2))
    )

    (call $push
      (call $register.segment.get (global.get $CS))
    )
    (call $push
      (global.get $IP)
    )  

    global.get $CS
    call $register.segment.set

    global.set $IP
  )

  ;; This is just an emulator, we do not have physical access to the hardware.
  (func $0x9b (; WAIT ;)
    unreachable
  )

  (func $0x9c (; PUSHF ;)
    (call $push
      (call $u16.convert_flags)
    )
  )
  (func $0x9d (; POPF ;)
    (call $flag.convert_u16 
      (call $pop)
    )
  )

  ;; This function should not be modifying $OF, hence the manual work-arounds.
  (func $0x9e (; SAHF ;)
    global.get $OF
    call $register.flag.get ;; Pushes (Saves) the current value of $OF onto the stack.

    (call $flag.convert_u16 (call $register.general.get8 (global.get $AH))) ;; This won't be using the above value.

    global.get $OF
    call $register.flag.set ;; Pops the value that is left on stack back into $OF again.
  )
  (func $0x9f (; LAHF ;)
    (call $register.general.set8 (global.get $AH) (i32.and (call $u16.convert_flags) (i32.const 0xff)))
  )

  (func $0xa0 (; MOV AL, Ob ;)
    (call $register.general.set8
      (global.get $AL)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0xa1 (; MOV AX, Ov ;)
    (call $register.general.set16
      (global.get $AX)
      (block (result i32)
        (call $ram.read16
          (global.get $seg)
          (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        )
        (call $step_ip (i32.const 2))
      )
    )
  )
  (func $0xa2 (; MOV Ob, AL ;)
    (call $ram.write8
      (global.get $seg)
      (block (result i32)
        (call $ram.read8
          (global.get $seg)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        )
        (call $step_ip (i32.const 1))
      )
      (call $register.general.get8 (global.get $AL))
    )
  )
  (func $0xa3 (; MOV Ov, AX ;)
    (call $ram.write16
      (global.get $seg)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
      (call $register.general.get16 (global.get $AX))
    )
  )

  (func $0xa4 (; MOVSB ;)
    (call $ram.write8
      (call $register.segment.get (global.get $ES))
      (call $register.general.get16 (global.get $DI))
      (call $ram.read8 (call $register.segment.get (global.get $seg) (call $register.general.get16 (global.get $SI))))
    )

    (call $register.general.set16
      (global.get $SI)
      (i32.add
        (call $register.general.get16 (global.get $SI))
        (select (i32.const -1) (i32.const 1)
                (call $register.flag.get (global.get $DF)))
      )
    )
    (call $register.general.set16
      (global.get $DI)
      (i32.add
        (call $register.general.get16 (global.get $DI))
        (select (i32.const -1) (i32.const 1)
                (call $register.flag.get (global.get $DF)))
      )
    )
  )
  (func $0xa5 (; MOVSW ;)
    (call $ram.write16 
      (call $register.segment.get (global.get $ES))
      (call $register.general.get16 (global.get $DI))
      (call $ram.read16 (call $register.segment.get (global.get $seg)) (call $register.general.get16 (global.get $SI)))
    )

    (call $register.general.set16
      (global.get $SI)
      (i32.add
        (call $register.general.get16 (global.get $SI))
        (select (i32.const -2) (i32.const 2)
                (call $register.flag.get (global.get $DF)))
      )
    )
    (call $register.general.set16
      (global.get $DI)
      (i32.add
        (call $register.general.get16 (global.get $DI))
        (select (i32.const -2) (i32.const 2)
                (call $register.flag.get (global.get $DF)))
      )
    )
  )

  (func $0xa6 (; CMPSB ;)
    (drop
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $ram.read8 (call $register.segment.get (global.get $ES) (call $register.general.get16 (global.get $DI))))
        (call $ram.read8 (call $register.segment.get (global.get $seg) (call $register.general.get16 (global.get $SI))))
      )
    )

    (call $register.general.set16
      (global.get $SI)
      (i32.add
        (call $register.general.get16 (global.get $SI))
        (select (i32.const -1) (i32.const 1)
                (call $register.flag.get (global.get $DF)))
      )
    )
    (call $register.general.set16
      (global.get $DI)
      (i32.add
        (call $register.general.get16 (global.get $DI))
        (select (i32.const -1) (i32.const 1)
                (call $register.flag.get (global.get $DF)))
      )
    )
  )
  (func $0xa7 (; CMPSW ;)
    (drop
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $ram.read16 (call $register.segment.get (global.get $ES) (call $register.general.get16 (global.get $DI))))
        (call $ram.read16 (call $register.segment.get (global.get $seg) (call $register.general.get16 (global.get $SI))))
      )
    )

    (call $register.general.set16
      (global.get $SI)
      (i32.add
        (call $register.general.get16 (global.get $SI))
        (select (i32.const -2) (i32.const 2)
                (call $register.flag.get (global.get $DF)))
      )
    )
    (call $register.general.set16
      (global.get $DI)
      (i32.add
        (call $register.general.get16 (global.get $DI))
        (select (i32.const -2) (i32.const 2)
                (call $register.flag.get (global.get $DF)))
      )
    )
  )

  (func $0xa8 (; TEST AL, Ib ;)
    (drop
      (call $set_zsp
        (i32.const 0)
        (i32.and
          (call $register.general.get8 (global.get $AL))
          (block (result i32)
            (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
            (call $step_ip (i32.const 1))
          )
        )
      )
    )
  )
  (func $0xa9 (; TEST AX, Iv ;)
    (drop
      (call $set_zsp
        (i32.const 1)
        (i32.and
          (call $register.general.get16 (global.get $AX))
          (block (result i32)
            (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
            (call $step_ip (i32.const 2))
          )
        )
      )
    )
  )

  (func $0xaa (; STOSB ;)
    (call $ram.write8
      (call $register.segment.get (global.get $ES))
      (call $register.general.get16 (global.get $DI))
      (call $register.general.get8 (global.get $AL))
    )

    (call $register.general.set16
      (global.get $DI)
      (i32.add
        (call $register.general.get16 (global.get $DI))
        (select (i32.const -1) (i32.const 1)
                (call $register.flag.get (global.get $DF)))
      )
    )
  )
  (func $0xab (; STOSW ;)
    (call $ram.write16
      (call $register.segment.get (global.get $ES))
      (call $register.general.get16 (global.get $DI))
      (call $register.general.get16 (global.get $AX))
    )

    (call $register.general.set16
      (global.get $DI)
      (i32.add
        (call $register.general.get16 (global.get $DI))
        (select (i32.const -2) (i32.const 2)
                (call $register.flag.get (global.get $DF)))
      )
    )
  )

  (func $0xac (; LODSB ;)
    (call $register.general.set8
      (global.get $AL)
      (call $ram.read8 (call $register.segment.get (global.get $seg)) (call $register.general.get16 (global.get $SI)))
    )

    (call $register.general.set16
      (global.get $SI)
      (i32.add
        (call $register.general.get16 (global.get $SI))
        (select (i32.const -1) (i32.const 1)
                (call $register.flag.get (global.get $DF)))
      )
    )
  )
  (func $0xad (; LODSW ;)
    (call $register.general.set16
      (global.get $AX)
      (call $ram.read16 (call $register.segment.get (global.get $seg)) (call $register.general.get16 (global.get $SI)))
    )

    (call $register.general.set16
      (global.get $SI)
      (i32.add
        (call $register.general.get16 (global.get $SI))
        (select (i32.const -2) (i32.const 2)
                (call $register.flag.get (global.get $DF)))
      )
    )
  )

  (func $0xae (; SCASB ;)
    (drop
      (call $checked_add 
        (i32.const 0) ;; 8-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get8 (global.get $AL))
        (call $ram.read8 (call $register.segment.get (global.get $ES) (call $register.general.get16 (global.get $DI))))
      )
    )

    (call $register.general.set16
      (global.get $SI)
      (i32.add
        (call $register.general.get16 (global.get $SI))
        (select (i32.const -1) (i32.const 1)
                (call $register.flag.get (global.get $DF)))
      )
    )
  )
  (func $0xaf (; SCASW ;)
    (drop
      (call $checked_add 
        (i32.const 1) ;; 16-Bit
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (call $register.general.get16 (global.get $AX))
        (call $ram.read16 (call $register.segment.get (global.get $ES) (call $register.general.get16 (global.get $DI))))
      )
    )

    (call $register.general.set16
      (global.get $SI)
      (i32.add
        (call $register.general.get16 (global.get $SI))
        (select (i32.const -2) (i32.const 2)
                (call $register.flag.get (global.get $DF)))
      )
    )
  )

  (func $0xb0 (; MOV AL, Ib ;)
    (call $register.general.set8
      (global.get $AL)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0xb1 (; MOV CL, Ib ;)
    (call $register.general.set8
      (global.get $CL)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0xb2 (; MOV DL, Ib ;)
    (call $register.general.set8
      (global.get $DL)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0xb3 (; MOV BL, Ib ;)
    (call $register.general.set8
      (global.get $BL)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0xb4 (; MOV AH, Ib ;)
    (call $register.general.set8
      (global.get $AH)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0xb5 (; MOV CH, Ib ;)
    (call $register.general.set8
      (global.get $CH)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0xb6 (; MOV DH, Ib ;)
    (call $register.general.set8
      (global.get $DH)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0xb7 (; MOV BH, Ib ;)
    (call $register.general.set8
      (global.get $BH)
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )

  (func $0xb8 (; MOV AX, Iv ;)
    (call $register.general.set16
      (global.get $AX)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )
  (func $0xb9 (; MOV CX, Iv ;)
    (call $register.general.set16
      (global.get $CX)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )
  (func $0xba (; MOV DX, Iv ;)
    (call $register.general.set16
      (global.get $DX)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )
  (func $0xbb (; MOV BX, Iv ;)
    (call $register.general.set16
      (global.get $BX)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )
  (func $0xbc (; MOV SP, Iv ;)
    (call $register.general.set16
      (global.get $SP)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )
  (func $0xbd (; MOV BP, Iv ;)
    (call $register.general.set16
      (global.get $BP)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )
  (func $0xbe (; MOV SI, Iv ;)
    (call $register.general.set16
      (global.get $SI)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )
  (func $0xbf (; MOV DI, Iv ;)
    (call $register.general.set16
      (global.get $DI)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )

  (func $0xc2 (; RET Iw ;)
    (call $register.general.set16 
      (global.get $SP)
      (i32.add
        (call $register.general.get16 (global.get $SP))
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
      )
    )

    (global.set $IP (call $pop))
  )
  (func $0xc3 (; RET ;)
    (global.set $IP (call $pop))
  )

  (func $0xc4 (; LES Gv, Mp ;)
    call $parse_address
    
    (call $register.general.set16
      (global.get $reg)
      (call $ram.direct_read16 (global.get $ea))
    )

    (call $register.general.set16
      (global.get $ES)
      (call $ram.direct_read16 (i32.add (global.get $ea) (i32.const 2)))
    )
  )
  (func $0xc5 (; LDS Gv, Mp ;)
    call $parse_address
    
    (call $register.general.set16
      (global.get $reg)
      (call $ram.direct_read16 (global.get $ea))
    )

    (call $register.general.set16
      (global.get $DS)
      (call $ram.direct_read16 (i32.add (global.get $ea) (i32.const 2)))
    )
  )
  (func $0xc6 (; MOV Eb, Ib ;)
    call $parse_address

    (call $logical_write8
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )
  )
  (func $0xc7 (; MOV Ev, Iv ;) 
    call $parse_address

    (call $logical_write16
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )

  (func $0xca (; RETF Iw ;)
    (call $register.general.set16 
      (global.get $SP)
      (i32.add
        (call $register.general.get16 (global.get $SP))
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
      )
    )

    (global.set $IP (call $pop))

    (call $register.segment.set 
      (global.get $CS)
      (call $pop)
    )
  )
  (func $0xcb (; RETF ;)
    (global.set $IP (call $pop))

    (call $register.segment.set 
      (global.get $CS)
      (call $pop)
    )
  )

  ;; Interrupts have not been implemented, yet.
  (func $0xcc (; INT 3 ;)
    unreachable
  )
  (func $0xcd (; INT Ib ;)
    (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
    )
    unreachable
  )
  (func $0xce (; INTO ;)
    (if 
      (call $register.flag.get (global.get $OF))
      (then
        unreachable
      )
    )
  )
  
  (func $0xcf (; IRET ;)
    (global.set $IP (call $pop))

    (call $register.segment.set 
      (global.get $CS)
      (call $pop)
    )

    (call $flag.convert_u16 (call $pop))
  )

  (func $0xd0 (; GRP2 Eb, 1 ;)
    call $parse_address
    
    (call $GRP2/8
      (call $logical_read8)
      (i32.const 1)
    )
  )
  (func $0xd1 (; GRP2 Ev, 1 ;)
    call $parse_address
    
    (call $GRP2/16
      (call $logical_read16)
      (i32.const 1)
    )
  )
  (func $0xd2 (; GRP2 Eb, CL ;)
    call $parse_address
    
    (call $GRP2/8
      (call $logical_read8)
      (call $register.general.get8 (global.get $CL))
    )
  )
  (func $0xd3 (; GRP2 Ev, CL ;)
    call $parse_address
    
    (call $GRP2/16
      (call $logical_read16)
      (call $i16.extend8_s ;; This opcode accepts both a byte AND a word as it's operands, so the byte might have to be sign-extended.
        (call $register.general.get8 (global.get $CL))
      )
    )
  )
  (func $0xd4 (; AAM ;)
    (call $register.general.set8
      (global.get $AH)
      (i32.div_u
        (call $register.general.get8 (global.get $AL))
        (i32.const 10)
      )
    )

    (call $register.general.set8
      (global.get $AL)
      (i32.rem_u
        (call $register.general.get8 (global.get $AL))
        (i32.const 10)
      )
    )
  )
  (func $0xd5 (; AAD ;)
    (call $register.general.set8
      (global.get $AL)
      (i32.add
        (i32.mul
          (call $register.general.get8 (global.get $AH))
          (i32.const 10)
        )
        (call $register.general.get8 (global.get $AL))
      )
    )

    (call $register.general.set8
      (global.get $AH)
      (i32.const 0)
    )
  )

  (func $0xd7 (; XLAT ;)
    (call $register.general.set8 
      (global.get $AL)
      (call $ram.read8
        (global.get $seg)
        (i32.add
          (call $register.general.get16 (global.get $BX))
          (call $register.general.get8 (global.get $AL))
        )
      )
    )
  )

  ;; The following OpCodes are only valid when a co-processor like x87 is present; but since we are
  ;; emulating this on fast, modern hardware, and co-processors were very rare and expensive back then; 
  ;; emulating a 8087 is out of this project's scope, and therefore considered invalid.
  (func $0xd8 (; ESC 0 ;)
    unreachable
  )
  (func $0xd9 (; ESC 1 ;)
    unreachable
  )
  (func $0xda (; ESC 2 ;)
    unreachable
  )
  (func $0xdb (; ESC 3 ;)
    unreachable
  )
  (func $0xdc (; ESC 4 ;)
    unreachable
  )
  (func $0xdd (; ESC 5 ;)
    unreachable
  )
  (func $0xde (; ESC 6 ;)
    unreachable
  )
  (func $0xdf (; ESC 7 ;)
    unreachable
  )

  (func $0xe0 (; LOOPNZ Jb ;)
    (call $jump 
      (i32.and
        (select (i32.const 1) (i32.const 0)
                (block (result i32)
                  (call $register.general.set16
                    (global.get $CX)
                    (i32.sub
                      (call $register.general.get16 (global.get $CX))
                      (i32.const 1)
                    )
                  )
                  (call $register.general.get16 (global.get $CX))
                ))
        (i32.eqz (call $register.flag.get (global.get $ZF)))
      )
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0xe1 (; LOOPZ Jb ;)
    (call $jump 
      (i32.and
        (select (i32.const 1) (i32.const 0)
                (block (result i32)
                  (call $register.general.set16
                    (global.get $CX)
                    (i32.sub
                      (call $register.general.get16 (global.get $CX))
                      (i32.const 1)
                    )
                  )
                  (call $register.general.get16 (global.get $CX))
                ))
        (global.get $ZF)
      )
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0xe2 (; LOOP Jb ;)
    (call $jump 
      (select (i32.const 1) (i32.const 0)
              (block (result i32)
                (call $register.general.set16
                  (global.get $CX)
                  (i32.sub
                    (call $register.general.get16 (global.get $CX))
                    (i32.const 1)
                  )
                )
                (call $register.general.get16 (global.get $CX))
              ))
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )
  (func $0xe3 (; LOOP Jb ;)
    (call $jump 
      (i32.eqz
        (block (result i32)
          (call $register.general.set16
            (global.get $CX)
            (i32.sub
              (call $register.general.get16 (global.get $CX))
              (i32.const 1)
            )
          )
          (call $register.general.get16 (global.get $CX))
        )
      )
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )

  ;; This is just an emulator, we do not have physical access to the hardware.
  (func $0xe4 (; IN AL, Ib ;)
    unreachable
  )
  (func $0xe5 (; IN AX, Ib ;)
    unreachable
  )
  (func $0xe6 (; OUT IB, AL ;)
    unreachable
  )
  (func $0xe7 (; OUT IB, AX ;)
    unreachable
  )

  (func $0xe8 (; CALL Jv ;)
    (call $step_ip
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS) (global.get $IP)))
        (call $step_ip (i32.const 2))

        (call $push (global.get $IP))
      )
    )
  )

  (func $0xe9 (; JMP Jv ;)
    (call $jump 
      (i32.const 1)
      (block (result i32)
        (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 2))
      )
    )
  )
  (func $0xea (; JMP Ap ;)
    (block (result i32)
      (call $ram.read16 (call $register.segment.get (global.get $CS) (global.get $IP)))
      (call $step_ip (i32.const 2))
    )

    (block (result i32)
      (call $ram.read16 (call $register.segment.get (global.get $CS) (global.get $IP)))
      (call $step_ip (i32.const 2))
    ) 

    global.get $CS
    call $register.segment.set

    global.set $IP
  )
  (func $0xeb (; JMP Jb ;)
    (call $jump 
      (i32.const 1)
      (call $i16.extend8_s
        (block (result i32)
          (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
          (call $step_ip (i32.const 1))
        )
      )
    )
  )

  (func $0xec (; IN AL, DX ;)
    unreachable
  )
  (func $0xed (; IN AX, DX ;)
    unreachable
  )
  (func $0xee (; OUT DX, AL ;)
    unreachable
  )
  (func $0xef (; OUT DX, AX ;)
    unreachable
  )

  ;; EXACT only emulates a single 8086, so LOCK should not be needed in a system with only a single processor, however
  ;; WebAssembly's threads (atomic) proposal could be used incase this is getting implemented.
  ;; https://github.com/WebAssembly/threads/blob/master/proposals/threads/Overview.md
  (func $0xf0 (; LOCK ;)
    nop
  )

  (func $0xf2 (local $opcode i32) (; REPNZ/REPNE ;)
    (local.set $opcode
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )

    (if
      (i32.or
        (i32.or
          (i32.or
            (i32.or (i32.eq (local.get $opcode) (i32.const 0xa4)) (i32.eq (local.get $opcode) (i32.const 0xa5)))
            (i32.or (i32.eq (local.get $opcode) (i32.const 0xa6)) (i32.eq (local.get $opcode) (i32.const 0xa7)))
          )
          (i32.or
            (i32.or (i32.eq (local.get $opcode) (i32.const 0xaa)) (i32.eq (local.get $opcode) (i32.const 0xab)))
            (i32.or (i32.eq (local.get $opcode) (i32.const 0xac)) (i32.eq (local.get $opcode) (i32.const 0xad)))
          )
        )
        (i32.or (i32.eq (local.get $opcode) (i32.const 0xae)) (i32.eq (local.get $opcode) (i32.const 0xaf)))
      )
      (then
        (block (loop
          (br_if 1 (i32.eqz (call $register.general.get16 (global.get $CX))))

          (call_indirect (local.get $opcode))

          (call $register.general.set16
            (global.get $CX)
            (i32.sub
              (call $register.general.get16 (global.get $CX))
              (i32.const 1)
            )
          )

          (br_if 0 (i32.eqz (call $register.flag.get (global.get $ZF))))
        ))
      )
    )
  )
  (func $0xf3 (local $opcode i32) (; REPZ/REPE/REP ;)
    (local.set $opcode
      (block (result i32)
        (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
        (call $step_ip (i32.const 1))
      )
    )

    (if
      (i32.or
        (i32.or
          (i32.or
            (i32.or (i32.eq (local.get $opcode) (i32.const 0xa4)) (i32.eq (local.get $opcode) (i32.const 0xa5)))
            (i32.or (i32.eq (local.get $opcode) (i32.const 0xa6)) (i32.eq (local.get $opcode) (i32.const 0xa7)))
          )
          (i32.or
            (i32.or (i32.eq (local.get $opcode) (i32.const 0xaa)) (i32.eq (local.get $opcode) (i32.const 0xab)))
            (i32.or (i32.eq (local.get $opcode) (i32.const 0xac)) (i32.eq (local.get $opcode) (i32.const 0xad)))
          )
        )
        (i32.or (i32.eq (local.get $opcode) (i32.const 0xae)) (i32.eq (local.get $opcode) (i32.const 0xaf)))
      )
      (then
        (block (loop
          (br_if 1 (i32.eqz (call $register.general.get16 (global.get $CX))))

          (call_indirect (local.get $opcode))

          (call $register.general.set16
            (global.get $CX)
            (i32.sub
              (call $register.general.get16 (global.get $CX))
              (i32.const 1)
            )
          )

          (br_if 0 (i32.eq (call $register.flag.get (global.get $ZF)) (i32.const 1)))
        ))
      )
    )
  )
  (func $0xf4 (; HLT ;)
    (global.set $program_length
      (global.get $IP)
    )
  )

  (func $0xf5 (; CMC ;)
    (call $register.flag.set 
      (global.get $CF)
      (call $i32.not (call $register.flag.get (global.get $CF)))
    )
  )

  (func $0xf6 (; GRP3a Eb ;)
    call $parse_address
    
    (call $GRP3
      (i32.const 0)
      (call $logical_read8)
    )
  )
  (func $0xf7 (; GRP3b Ev ;)
    call $parse_address
    
    (call $GRP3
      (i32.const 1)
      (call $logical_read16)
    )
  )

  (func $0xf8 (; CLC ;)
    (call $register.flag.set
      (global.get $CF)
      (i32.const 0)
    )
  )
  (func $0xf9 (; STC ;)
    (call $register.flag.set
      (global.get $CF)
      (i32.const 1)
    )
  )
  (func $0xfa (; CLI ;)
    (call $register.flag.set
      (global.get $IF)
      (i32.const 0)
    )
  )
  (func $0xfb (; STI ;)
    (call $register.flag.set
      (global.get $IF)
      (i32.const 1)
    )
  )
  (func $0xfc (; CLD ;)
    (call $register.flag.set
      (global.get $DF)
      (i32.const 0)
    )
  )
  (func $0xfd (; STD ;)
    (call $register.flag.set
      (global.get $DF)
      (i32.const 1)
    )
  )

  (func $0xfe (; GRP4 Eb ;)
    call $parse_address


    global.get $CF
    call $register.flag.get

    (call $logical_write8
      (select 
        (call $checked_add 
          (i32.const 0) ;; 8-Bit
          (i32.const 1) ;; Subtraction
          (i32.const 0) ;; No Carry
          (call $logical_read8)
          (i32.const 1)
        )
        (call $checked_add 
          (i32.const 0) ;; 8-Bit
          (i32.const 0) ;; Addition
          (i32.const 0) ;; No Carry
          (call $logical_read8)
          (i32.const 1)
        )
        (global.get $reg))
    )

    global.get $CF
    call $register.flag.set
  )
  (func $0xff (; GRP5 Ev ;)
    call $parse_address


    (block (block (block (block (block (block (block (global.get $reg)
                (br_table
                  0         ;; reg == {000b} --> (br 0)[INC]
                  1         ;; reg == {001b} --> (br 1)[DEC]
                  2         ;; reg == {010b} --> (br 2)[CALL]
                  3         ;; reg == {011b} --> (br 3)[CALL Mp]
                  4         ;; reg == {100b} --> (br 4)[JMP]
                  5         ;; reg == {101b} --> (br 5)[JMP Mp]
                  6         ;; 000b > reg OR reg >= 110b --> (br 7 (Default))[PUSH]
                ))
                ;; Target for (br 0)
                (block
                  (call $logical_write16
                    (call $checked_add 
                      (i32.const 1) ;; 16-Bit
                      (i32.const 0) ;; Addition
                      (i32.const 0) ;; No Carry
                      (call $logical_read16)
                      (i32.const 1)
                    )
                  )

                  return
                ))
              ;; Target for (br 1)
              (block
                (call $logical_write16
                  (call $checked_add 
                    (i32.const 1) ;; 16-Bit
                    (i32.const 1) ;; Subtraction
                    (i32.const 0) ;; No Carry
                    (call $logical_read16)
                    (i32.const 1)
                  )
                )

                return
              ))
            ;; Target for (br 2)
            (block
              (call $push
                (global.get $IP)
              )  
              (global.set $IP
                (call $logical_read16)
              )

              return
            ))
          ;; Target for (br 3)
          (block
            (call $push
              (call $register.segment.get (global.get $CS))
            )
            (call $push
              (global.get $IP)
            )  

            (global.set $IP
              (call $ram.direct_read16 (global.get $ea))
            )
            (call $register.segment.set
              (global.get $CS)
              (call $ram.direct_read16 (i32.add (global.get $ea) (i32.const 2)))
            )

            return
          ))
        ;; Target for (br 4)
        (block
          (global.set $IP
            (call $logical_read16)
          )

          return
        ))
      ;; Target for (br 5)
      (block
        (global.set $IP
          (call $ram.direct_read16 (global.get $ea))
        )
        (call $register.segment.set
          (global.get $CS)
          (call $ram.direct_read16 (i32.add (global.get $ea) (i32.const 2)))
        )

        return
      ))
    ;; (Default) Target for (br 6)
    (block
      (call $push
        (call $logical_read16)
      )

      return
    )
  )


  (; OpCode Extensions (http://www.mlsite.net/8086/#tbl_ext) ;)
  (func $GRP1/8 (param $destination i32) (param $source i32)
    (call $logical_write8
      (call $GRP1 (i32.const 0) (local.get $destination) (local.get $source))
    )
  )
  (func $GRP1/16 (param $destination i32) (param $source i32)
    (call $logical_write16
      (call $GRP1 (i32.const 1) (local.get $destination) (local.get $source))
    )
  )
  (func $GRP1 (param $mode i32) (param $destination i32) (param $source i32)
              (result i32)
    (block (block (block (block (block (block (block (block (global.get $reg)
                  (br_table
                    0         ;; reg == {000b} --> (br 0)[ADD]
                    1         ;; reg == {001b} --> (br 1)[OR]
                    2         ;; reg == {010b} --> (br 2)[ADC]
                    3         ;; reg == {011b} --> (br 3)[SBB]
                    4         ;; reg == {100b} --> (br 4)[AND]
                    5         ;; reg == {101b} --> (br 5)[SUB]
                    6         ;; reg == {110b} --> (br 6)[XOR]
                    7         ;; 000b > reg OR reg >= 111b --> (br 7 (Default))[CMP]
                  ))
                  ;; Target for (br 0)
                  (return
                    (call $checked_add 
                      (local.get $mode)
                      (i32.const 0) ;; Addition
                      (i32.const 0) ;; No Carry
                      (local.get $destination)
                      (local.get $source)
                    )
                  ))
                ;; Target for (br 1)
                (return
                  (i32.or
                    (local.get $destination)
                    (local.get $source)
                  )
                ))
              ;; Target for (br 2)
              (return
                (call $checked_add 
                  (local.get $mode)
                  (i32.const 0) ;; Addition
                  (i32.const 1) ;; Carry
                  (local.get $destination)
                  (local.get $source)
                )
              ))
            ;; Target for (br 3)
            (return
              (call $checked_add 
                (local.get $mode)
                (i32.const 1) ;; Subtraction
                (i32.const 1) ;; Carry
                (local.get $destination)
                (local.get $source)
              )
            ))
          ;; Target for (br 4)
          (return
            (i32.and
              (local.get $destination)
              (local.get $source)
            )
          ))
        ;; Target for (br 5)
        (return
          (call $checked_add 
            (local.get $mode)
            (i32.const 1) ;; Subtraction
            (i32.const 0) ;; No Carry
            (local.get $destination)
            (local.get $source)
          )
        ))
      ;; Target for (br 6)
      (return
        (i32.xor
          (local.get $destination)
          (local.get $source)
        )
      ))
    ;; (Default) Target for (br 7)
    (return
      (call $checked_add 
        (local.get $mode)
        (i32.const 1) ;; Subtraction
        (i32.const 0) ;; No Carry
        (local.get $destination)
        (local.get $source)
      )
    )
  )

  (func $GRP2/8 (param $destination i32) (param $source i32)
    (call $logical_write8
      (call $GRP2 (i32.const 0) (local.get $destination) (local.get $source))
    )
  )
  (func $GRP2/16 (param $destination i32) (param $source i32)
    (call $logical_write16
      (call $GRP2 (i32.const 1) (local.get $destination) (local.get $source))
    )
  )
  (func $GRP2 (param $mode i32) (param $destination i32) (param $source i32)
              (result i32) 
              (local $temp i32)
    (block (block (block (block (block (block (block (global.get $reg)
                (br_table
                  0         ;; reg == {000b} --> (br 0)[ROL]
                  1         ;; reg == {001b} --> (br 1)[ROR]
                  2         ;; reg == {010b} --> (br 2)[RCL]
                  3         ;; reg == {011b} --> (br 3)[RCR]
                  4         ;; reg == {100b} --> (br 4)[SHL]
                  5         ;; reg == {101b} --> (br 5)[SHR]
                  6         ;; 000b > reg OR reg >= 110b --> (br 7 (Default))[SAR]
                ))
                ;; Target for (br 0)
                (block
                  (local.set $temp (i32.rotl (local.get $destination) (local.get $source)))

                  (call $register.flag.set 
                    (global.get $CF)
                    (i32.shr_u (local.get $destination) (i32.const 15))  
                  )

                  (call $register.flag.set 
                    (global.get $CF) 
                    (i32.and (local.get $destination) (i32.const 1))
                  )

                  (call $register.flag.set
                    (global.get $OF)
                    (i32.xor
                      (i32.shr_u (local.get $destination) (select (i32.const 15) (i32.const 7)
                                                          (local.get $mode))
                      )
                      (call $register.flag.get (global.get $CF))
                    )
                  )

                  (return (local.get $temp))
                ))
              ;; Target for (br 1)
              (block
                (local.set $temp (i32.rotr (local.get $destination) (local.get $source)))

                (call $register.flag.set 
                  (global.get $CF) 
                  (i32.shr_u (local.get $temp) (select (i32.const 15) (i32.const 7)
                                              (local.get $mode))
                  )
                )

                (call $register.flag.set
                  (global.get $OF)
                  (i32.xor
                    (i32.shr_u (local.get $destination) (select (i32.const 15) (i32.const 7)
                                                         (local.get $mode))
                    )
                    (call $register.flag.get (global.get $CF))
                  )
                )

                (return (local.get $temp))
              ))
            ;; Target for (br 2)
            (block
              (local.set $temp 
                (i32.rotl
                  (i32.or ;; Adds $CF to the extended input (RCL rotates through the carry flag).
                    (call $register.flag.get (global.get $CF))
                    (i32.shl (local.get $destination) (i32.const 1)) ;; Extends the input by 1 bit.
                  )
                  (local.get $source)
                )
              )

              (call $register.flag.set 
                (global.get $CF)
                (i32.shr_u (local.get $destination) (i32.const 15))  
              )

              (call $register.flag.set 
                (global.get $CF) 
                (i32.and (local.get $destination) (i32.const 1))
              )

              (call $register.flag.set
                (global.get $OF)
                (i32.xor
                  (i32.shr_u (local.get $destination) (select (i32.const 15) (i32.const 7)
                                                      (local.get $mode))
                  )
                  (call $register.flag.get (global.get $CF))
                )
              )

              (return (local.get $temp))
            ))
          ;; Target for (br 3)
          (block
            (local.set $temp 
              (i32.rotr
                (i32.or ;; Adds $CF to the extended input (RCL rotates through the carry flag).
                  (i32.shl (local.get $destination) (i32.const 1)) ;; Extends the input by 1 bit.
                  (call $register.flag.get (global.get $CF))
                )
                (local.get $source)
              )
            )

            (call $register.flag.set 
              (global.get $CF) 
              (i32.shr_u (local.get $temp) (select (i32.const 15) (i32.const 7)
                                          (local.get $mode))
              )
            )

            (call $register.flag.set
              (global.get $OF)
              (i32.xor
                (i32.shr_u (local.get $destination) (select (i32.const 15) (i32.const 7)
                                                      (local.get $mode))
                )
                (call $register.flag.get (global.get $CF))
              )
            )

            (return (local.get $temp))
          ))
        ;; Target for (br 4)
        (block
          (local.set $temp
            (i32.shl
              (local.get $destination)
              (local.get $source)
            )
          )

          (call $register.flag.set 
            (global.get $CF) 
            (i32.shr_u (local.get $temp) (select (i32.const 16) (i32.const 8)
                                         (local.get $mode))
            )
          )

          (local.set $temp (i32.and (local.get $temp) (i32.const 255)))

          (call $register.flag.set
            (global.get $OF)
            (i32.xor
              (i32.shr_u (local.get $temp) (select (i32.const 15) (i32.const 7)
                                                   (local.get $mode))
              )
              (call $register.flag.get (global.get $CF))
            )
          )

          (local.get $temp)

          return
        ))
      ;; Target for (br 5)
      (block
        (local.set $temp
          (i32.shr_u
            (local.get $destination)
            (local.get $source)
          )
        )

        (call $register.flag.set 
          (global.get $CF) 
          (i32.and (local.get $destination) (i32.const 1))
        )

        (call $register.flag.set
          (global.get $OF)
          (i32.xor
            (i32.shr_u (local.get $temp) (select (i32.const 15) (i32.const 7)
                                                 (local.get $mode))
            )
            (i32.shr_u (local.get $destination) (select (i32.const 15) (i32.const 7)
                                                        (local.get $mode))
            )
          )
        )

        (local.get $temp)

        return
      ))
    ;; (Default) Target for (br 6)
    (block (result i32)
      (local.set $temp
        (i32.shr_s
          (i32.shr_s 
            (i32.shl (local.get $destination) (select (i32.const 16) (i32.const 24)
                                                      (local.get $mode))) 
            (select (i32.const 16) (i32.const 24) 
                    (local.get $mode))
          )
          (local.get $source)
        )
      )

      (call $register.flag.set 
        (global.get $CF) 
        (i32.and (local.get $destination) (i32.const 1))
      )

      ;; Impossible for $OF to be enabled after performing an arithmetical right-shift.
      (call $register.flag.set
        (global.get $OF)
        (i32.const 0)
      )

      (local.get $temp)

      return
    )
  )
  
  (func $GRP3 (param $mode i32) (param $destination i32)
              (local $temp i32)
    (block (block (block (block (block (block (block (block (global.get $reg)
                  (br_table
                    0         ;; reg == {000b} --> (br 0)[TEST Eb, Ib / TEST Ev, Iv]
                    1         ;; reg == {001b} --> (br 1)[UNDF]
                    2         ;; reg == {010b} --> (br 2)[NOT]
                    3         ;; reg == {011b} --> (br 3)[NEG]
                    4         ;; reg == {100b} --> (br 4)[MUL]
                    5         ;; reg == {101b} --> (br 5)[IMUL]
                    6         ;; reg == {110b} --> (br 6)[DIV]
                    7         ;; 000b > reg OR reg >= 111b --> (br 7 (Default))[IDIV]
                  ))
                  ;; Target for (br 0)
                  (block
                    (drop
                      (call $set_zsp
                        (local.get $mode)
                        (i32.and
                          (local.get $destination)
                          (select
                            (block (result i32)
                              (call $ram.read16 (call $register.segment.get (global.get $CS)) (global.get $IP))
                              (call $step_ip (i32.const 2))
                            )
                            (block (result i32)
                              (call $ram.read8 (call $register.segment.get (global.get $CS)) (global.get $IP))
                              (call $step_ip (i32.const 1))
                            ) 
                            (local.get $mode))
                        )
                      )
                    )

                    return
                  ))
                ;; Target for (br 1)
                (block
                  return
                ))
              ;; Target for (br 2)
              (block
                (local.set $temp
                  (i32.and
                    (i32.xor (local.get $destination) (i32.const -1))
                    (select (i32.const 65535) (i32.const 255) 
                            (local.get $mode))
                  )
                )
                (if (i32.eqz (local.get $mode))
                  (then ;; 8-Bit
                    (call $logical_write8 (local.get $temp))
                  )
                  (else ;; 16-Bit
                    (call $logical_write16 (local.get $temp))
                  )
                )

                return
              ))
            ;; Target for (br 3)
            (block
              (local.set $temp
                (call $i32.neg (local.get $destination))
              )
              (if (i32.eqz (local.get $mode))
                (then ;; 8-Bit
                  (call $logical_write8 (local.get $temp))
                )
                (else ;; 16-Bit
                  (call $logical_write16 (local.get $temp))
                )
              )

              return
            ))
          ;; Target for (br 4)
          (block
            (if (i32.eqz (local.get $mode))
              (then ;; 8-Bit
                (call $register.general.set8
                  (global.get $AX)
                  (call $set_zsp
                    (i32.const 0)
                    (i32.mul
                      (call $register.general.get8 (global.get $AL))
                      (local.get $destination)
                    )
                  )
                )
              )
              (else ;; 16-Bit
                (local.set $temp
                  (call $set_zsp
                    (i32.const 1)
                    (i32.mul
                      (call $register.general.get16 (global.get $AX))
                      (local.get $destination)
                    )
                  )
                )

                (call $register.general.set8
                  (global.get $AX)
                  (i32.and
                    (local.get $temp)
                    (i32.const 65535)
                  )
                )
                (call $register.general.set8
                  (global.get $DX)
                  (i32.shr_u
                    (local.get $temp)
                    (i32.const 16)
                  )
                )
              )
            )

            (local.set $temp 
              (select (call $register.general.get16 (global.get $DX)) (call $register.general.get8 (global.get $AH))
                      (local.get $mode))
            )
            (call $register.flag.set
              (global.get $CF)
              (local.get $temp)
            )
            (call $register.flag.set
              (global.get $OF)
              (local.get $temp)
            )

            return
          ))
        ;; Target for (br 5)
        (block
          (if (i32.eqz (local.get $mode))
            (then ;; 8-Bit
              (call $register.general.set8
                (global.get $AX)
                (call $set_zsp
                  (i32.const 0)
                  (i32.mul
                    (call $register.general.get8 (global.get $AL))
                    (local.get $destination)
                  )
                )
              )
            )
            (else ;; 16-Bit
              (local.set $temp
                (call $set_zsp
                  (i32.const 1)
                  (i32.mul
                    (call $register.general.get16 (global.get $AX))
                    (local.get $destination)
                  )
                )
              )

              (call $register.general.set16
                (global.get $AX)
                (i32.and
                  (local.get $temp)
                  (i32.const 65535)
                )
              )
              (call $register.general.set16
                (global.get $DX)
                (i32.shr_u
                  (local.get $temp)
                  (i32.const 16)
                )
              )
            )
          )

          (local.set $temp 
            (select (call $register.general.get16 (global.get $DX)) (call $register.general.get8 (global.get $AH))
                    (local.get $mode))
          )
          (call $register.flag.set
            (global.get $CF)
            (local.get $temp)
          )
          (call $register.flag.set
            (global.get $OF)
            (local.get $temp)
          )

          return
        ))
      ;; Target for (br 6)
      (block
        (if (i32.eqz (local.get $mode))
          (then ;; 8-Bit
            (call $register.general.set8
              (global.get $AX)
              (call $set_zsp
                (i32.const 0)
                (i32.div_u
                  (call $register.general.get8 (global.get $AL))
                  (local.get $destination)
                )
              )
            )
          )
          (else ;; 16-Bit
            (local.set $temp
              (call $set_zsp
                (i32.const 1)
                (i32.div_u
                  (call $register.general.get16 (global.get $AX))
                  (local.get $destination)
                )
              )
            )

            (call $register.general.set16
              (global.get $AX)
              (i32.and
                (local.get $temp)
                (i32.const 65535)
              )
            )
            (call $register.general.set16
              (global.get $DX)
              (i32.shr_u
                (local.get $temp)
                (i32.const 16)
              )
            )
          )
        )

        return
      ))
    ;; (Default) Target for (br 7)
    (block
      (if (i32.eqz (local.get $mode))
        (then ;; 8-Bit
          (call $register.general.set8
            (global.get $AX)
            (call $set_zsp
              (i32.const 0)
              (i32.div_s
                (i32.shr_s
                  (i32.shl (call $register.general.get8 (global.get $AL)) (i32.const 24))
                  (i32.const 24)
                )
                (i32.shr_s
                  (i32.shl (local.get $destination) (i32.const 24))
                  (i32.const 24)
                )
              )
            )
          )
        )
        (else ;; 16-Bit
          (local.set $temp
            (call $set_zsp
              (i32.const 1)
              (i32.div_s
                (i32.shr_s
                  (i32.shl (call $register.general.get16 (global.get $AX)) (i32.const 16))
                  (i32.const 16)
                )
                (i32.shr_s
                  (i32.shl (local.get $destination) (i32.const 16))
                  (i32.const 16)
                )
              )
            )
          )

          (call $register.general.set16
            (global.get $AX)
            (i32.and
              (local.get $temp)
              (i32.const 65535)
            )
          )
          (call $register.general.set16
            (global.get $DX)
            (i32.shr_u
              (local.get $temp)
              (i32.const 16)
            )
          )
        )
      )

      return
    )
  )


  (; Undocumented or duplicate OpCodes ;)
  ;; Most illegal OpCodes would just map to other documented instructions (e.g., 0x60 - 0x6f --> 0x70 – 0x7f);
  ;; while a few others such as 'SALC' actually did something useful.
  ;;
  ;; However, a real 8086 (or anything earlier than 80186) would do nothing when encountering a truly invalid OpCode.
  ;; This emulator aims to be fully compatible _only_ (i.e., no co-processors) with the original 8086, so it supports the 
  ;; redundant OpCodes or others like 'SALC'.  Also, several OpCodes (e.g., 0xd8 - 0xdf) are only valid when a co-processor like x87 is present; 
  ;; but since we are emulating this on fast, modern hardware, and co-processors were very rare and expensive back then; 
  ;; emulating a 8087 is out of this project's scope, and therefore considered invalid.
  (func $0x0f (; POP CS ;)
    (call $register.segment.set 
      (global.get $CS)
      (call $pop)
    )
  )

  (func $0x60 (; equivalent: 70h ;)
    (call $0x70)
  )
  (func $0x61 (; equivalent: 71h ;)
    (call $0x71)
  )
  (func $0x62 (; equivalent: 72h ;)
    (call $0x72)
  )
  (func $0x63 (; equivalent: 73h ;)
    (call $0x73)
  )
  (func $0x64 (; equivalent: 74h ;)
    (call $0x74)
  )
  (func $0x65 (; equivalent: 75h ;)
    (call $0x75)
  )
  (func $0x66 (; equivalent: 76h ;)
    (call $0x76)
  )
  (func $0x67 (; equivalent: 77h ;)
    (call $0x77)
  )
  (func $0x68 (; equivalent: 78h ;)
    (call $0x78)
  )
  (func $0x69 (; equivalent: 79h ;)
    (call $0x79)
  )
  (func $0x6a (; equivalent: 7ah ;)
    (call $0x7a)
  )
  (func $0x6b (; equivalent: 7bh ;)
    (call $0x7b)
  )
  (func $0x6c (; equivalent: 7ch ;)
    (call $0x7c)
  )
  (func $0x6d (; equivalent: 7dh ;)
    (call $0x7d)
  )
  (func $0x6e (; equivalent: 7eh ;)
    (call $0x7e)
  )
  (func $0x6f (; equivalent: 7fh ;)
    (call $0x7f)
  )

  (func $0xc0 (; equivalent: c2h ;)
    (call $0xc2)
  )
  (func $0xc1 (; equivalent: c3h ;)
    (call $0xc3)
  )
  (func $0xc8 (; equivalent: cah ;)
    (call $0xca)
  )
  (func $0xc9 (; equivalent: cbh ;)
    (call $0xcb)
  )

  ;; this OpCode sets AL to 255 if the carry flag is set; 0 otherwise.
  (func $0xd6 (; SALC ;)
    (call $register.general.set8 
      (global.get $AL)
      (select (i32.const 0xff) (i32.const 0x00)
              (call $register.flag.get (global.get $CF)))
    )
  )

  (func $0xf1 (; equivalent: f0h ;)
    (call $0xf0)
  )


)
