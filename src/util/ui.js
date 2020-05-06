"use strict";


export default updateUI;



export async function updateUI(instance) {
    await updateRegisters(instance);
}

async function updateRegisters(instance) {
    const registers = document.getElementsByClassName("register");
    // x = new Uint32Array(instance.exports.memory.buffer)[offset - 1];
    for (let offset = 0; offset < registers.length; offset++)
        registers[offset].innerHTML = new Uint8Array(instance.exports.memory.buffer, offset, 2);
};