(module
  (; memory section ;)
  ;; Maximum accessible memory (initial) by a Z80 equals to '0.9765625' WASM memory pages or 64KB.
  (memory 1 16384 (;shared;))

  (; global section ;)
  
  (; Import Section ;)

  (; Export Section ;)
  (export "memory" (memory 0))
  (export "main" (func $main))

  (; Start Section ;)
  (func $main)
)
