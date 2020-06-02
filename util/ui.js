"use strict";


export default updateUI;



// byte and word buffers only exist as separate parameters because
// calculating them based on the instance each time updateUI is run
// is going to be resource-intensive, so we only allocate them once
// inside our script tag.
export async function updateUI(instance, byteBuffer, wordBuffer) {
    await updateRegisters(instance, byteBuffer, wordBuffer);
}

async function updateRegisters(instance, byteBuffer, wordBuffer) {
    const registers = document.getElementsByClassName("register");

    
    for (let offset = 0; offset < 8; offset++) {
        // 16-Bit General-purpose and Index registers
        registers[offset].innerHTML = wordBuffer[offset];
        // 8-Bit register decodes
        registers[offset + 8].innerHTML = byteBuffer[offset];
    }

    for (let offset = 8; offset < 12; offset++) {
        // Segment registers
        registers[offset + 8].innerHTML = wordBuffer[offset];
    }

    // Flag registers do not follow a uniform order, hence the manual assignment.
    registers[20].innerHTML = byteBuffer[24];
    registers[21].innerHTML = byteBuffer[26];
    registers[22].innerHTML = byteBuffer[28];
    registers[23].innerHTML = byteBuffer[30];
    registers[24].innerHTML = byteBuffer[31];
    registers[25].innerHTML = byteBuffer[32];
    registers[26].innerHTML = byteBuffer[33];
    registers[27].innerHTML = byteBuffer[34];
    registers[28].innerHTML = byteBuffer[35];

    // Program counter
    registers[29].innerHTML = instance.exports.IP.value;
}