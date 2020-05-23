"use strict";


export default updateUI;



export async function updateUI(instance) {
    await updateRegisters(instance);
}

async function updateRegisters(instance) {
    const registers = document.getElementsByClassName("register");

    const byteBuffer = new Uint8Array(instance.exports.memory.buffer);
    const wordBuffer = new Uint16Array(instance.exports.memory.buffer);


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