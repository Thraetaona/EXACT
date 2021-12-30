<div align="center">

  <h1><code>EXACT</code></h1>

  <p>
    <strong>A Bare-Metal Intel 8086 Emulator Written In Raw WebAssembly.</strong>
  </p>

  <h3>
    <a href="https://Thraetaona.github.io/EXACT/">Demo</a>
    <span> | </span>
    <a href="https://github.com/Thraetaona/EXACT/issues">Issue Tracker</a>
    <span> | </span>
    <a href="https://github.com/Thraetaona/EXACT/actions">CI</a>
    <span> | </span>
    <a href="https://github.com/Thraetaona/EXACT/projects">Roadmap</a>
    <span> | </span>
    <a href="https://github.com/Thraetaona/EXACT/releases">Releases</a>
  </h3>
  
</div>

***

## Abstract
EXACT is an acronym for '**E**mulating **X**86 i**A**PX **C**PU on Ne**T**'. \
[Working demonstration with examples deployed at GitHub Pages.](https://Thraetaona.github.io/EXACT)

This project was primarily done for two reasons:
* *In favor of [RASM](https://github.com/Thraetaona/RASM)*, which is basically a work-in-progress Game Engine written in Rust.  Getting fluent in WebAssembly meant writing efficient code and eased its debugging.
* *Experience*.  an in-depth study of processor that still has alot in common with x86_64 will surely assist in writing optimized code; even though the 8086 lacked any concepts of caches (as an example).

The emulator's source code has been thoroughly documented, except in places where doing so would have been considered extremely verbose or otherwise obivous.

## How To Compile And Run
The easiest way to get EXACT up-and-running is by downloading the latest pre-built binaries from the [releases section](https://github.com/Thraetaona/EXACT/releases), unpacking the .zip file, running the provided Python script (serve.py) and lastly visiting http://localhost:8086/ using an updated browser that supports WebAssembly. <br>
If done correctly, you should see a page identical to this: https://Thraetaona.github.io/EXACT


Alternatively you could follow the below instructions for a manual build:

---

First install the official WebAssembly Binary Toolkit ("WABT") using your package manager or from [their GitHub Repository](https://github.com/WebAssembly/wabt).

Next, assemble the source code with: 
```
wat2wasm ./src/8086.wat -o ./src/8086.wasm
```

<sub>
The resulting bytecode could optionally be further optimized using: <br>
  <code>
    wasm-opt -O4 --enable-mutable-globals --flatten -iit --dfo --directize --precompute ./src/8086.wasm -o ./src/8086.wasm
  </code>
  <br>
(But be aware that aggressive optimizations could result in inaccuracies or unexpected bugs and side effects.) <br>
</sub>
<br>

And finally host the compiled binary along with the HTML file (./src/index.html) at a local or live webserver with **application/wasm** mimetype; and visit it using a browser supporting the base WebAssembly standard (And the exported mutable globals porposal), such as Google Chrome, Mozilla FireFox or the Chromium-based Microsoft Edge.

<sub>
You could also add your own or just assemble all the included source files in the ./examples folder using the Netwide Assembler ("NASM") with <code>for f in ./examples/*.asm; do nasm -O0 -f bin "$f";done</code>, if you also host these binary files alongside the previous files, they will appear under the "Examples" dropdown menu in the GUI.
</sub>
 
***

## Features

![Overview of EXACT](https://user-images.githubusercontent.com/42461518/147782528-bdb22a37-e85a-4901-996f-bd3260a90f8e.jpg)

| Emulation Capability | Current Status |
| :---: | :--- |
| Instructions<sup>1</sup> | All, including illegal OpCodes |
| Registers | Both User-accessible registers and Reserved Flags are available |
| RAM | Supports up to 2^20 unique segmentated addresses with 16/8 Bit interfaces for interactions |
| Multimedia (GPU, sound, etc)<sup>2</sup> | - |

---

<sub>
1-Interupts or Instructions that require physical hardware access are not implemented. <br>
2-emulating external hardware, a graphical display or interrupts should be easy given that the basis required for them is already finished. <br>
</sub>

---
