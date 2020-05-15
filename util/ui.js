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

    registers[20].innerHTML = instance.exports.CF.value;
    registers[21].innerHTML = instance.exports.PF.value;
    registers[22].innerHTML = instance.exports.AF.value;
    registers[23].innerHTML = instance.exports.OF.value;
    registers[24].innerHTML = instance.exports.ZF.value;
    registers[25].innerHTML = instance.exports.SF.value;
    registers[26].innerHTML = instance.exports.TF.value;
    registers[27].innerHTML = instance.exports.IF.value;
    registers[28].innerHTML = instance.exports.DF.value;
}