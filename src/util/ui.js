"use strict";


export default updateUI;



export async function updateUI(instance) {
    await updateRegisters(instance);
}

async function updateRegisters(instance) {
    const registers = document.getElementsByClassName("register");


    for (let offset = 0; offset < 8; offset++) {
        // 16-Bit General-purpose and Index registers
        registers[offset].innerHTML = new Uint16Array(instance.exports.memory.buffer)[offset];
        // 8-Bit register decodes
        registers[offset + 8].innerHTML = new Uint8Array(instance.exports.memory.buffer)[offset];
    }

    for (let offset = 0; offset < 4; offset++) {
        // Segment registers
        registers[offset + 16].innerHTML = new Uint16Array(instance.exports.memory.buffer)[offset + 8];
    }

    // Flag registers do not follow a uniform order, hence the manual assignment.
    const flags = new Uint8Array(instance.exports.memory.buffer);
    registers[20].innerHTML = flags[24];
    registers[21].innerHTML = flags[26];
    registers[22].innerHTML = flags[28];
    registers[23].innerHTML = flags[30];
    registers[24].innerHTML = flags[31];
    registers[25].innerHTML = flags[32];
    registers[26].innerHTML = flags[33];
    registers[27].innerHTML = flags[34];
    registers[28].innerHTML = flags[35];
}