<div align="center">

  <h1><code>EXACT</code></h1>

  <img src="" alt="Logo">

  <p>
    <strong>A Bare-Metal Intel 8086 Emulator Written In Raw WebAssembly.</strong>
  </p>

  <p>
    <a href="https://github.com/Thraetaona/EXACT/actions"><img alt="GitHub Actions CI status" src="https://github.com/Thraetaona/EXACT/workflows/EXACT/badge.svg"></a>
  </p>

  <h3>
    <a href="https://Thraetaona.github.io/EXACT/">Website</a>
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
[Live demo with examples deployed at GitHub Pages.](https://Thraetaona.github.io/EXACT)

This project was primarily done for two reasons:
* *In favor of [RASM](https://github.com/Thraetaona/RASM)*, which is basically a work-in-progress Game Engine written in Rust.  Getting fluent in WebAssembly meant writing efficient code and eased its debugging.
* *Experience*.  an in-depth study of processor that still has alot in common with x86_64 will surely assist in writing optimized code; even though the 8086 lacked any concepts of caches (as an example).

The emulator has been thoroughly documented, except in places where doing so would have been considered extremely verbose or otherwise obivous.


***

## Features


| Emulation Capability | Current Status |
| :--- | ---: |
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
