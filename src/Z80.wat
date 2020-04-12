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


  (; Table Section ;)
  (table $opcodes 252 255 funcref)
  (elem (i32.const 0) $0x0 $0x1 $0x2 $0x3 $0x4 $0x5 $0x6 $0x7 $0x8 $0x9 $0xa $0xb $0xc $0xd $0xe $0xf
  $0x10 $0x11 $0x12 $0x13 $0x14 $0x15 $0x16 $0x17 $0x18 $0x19 $0x1a $0x1b $0x1c $0x1d $0x1e $0x1f
  
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
