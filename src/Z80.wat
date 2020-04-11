;; Module-level documentation (Overview) resides in the 'README.md' file.


(module $cpu
  (; Memory Section ;)
  ;; It is possible to define memory within webassembly like this "(memory 1 16384 shared)",
  ;; however, we currently define it in the host environment and simply import it to this module.
  ;; Where it's defined has no effect on performance, it is purely done to keep the emulator 'modular'
  ;; in a way that it expects memory, basic IO and other components to be provided externally;
  ;; just as a real, physical Z80 would.

  (; Import Section ;)
  (import "env" "memory" (memory 1 16384 shared))

  (; Export Section ;)
  (export "start" (func $start))

  (; Global Section ;)
  (global $A0 f32 (f32.const 0))
  (global $A1 (mut f32) (f32.const 0))

  (; Table Section ;)

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
