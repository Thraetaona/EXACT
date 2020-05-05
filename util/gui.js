"use strict";


export default updateUI;



export async function updateUI(memory) {
    await updateRegisters(memory);
}

async function updateRegisters(memory) {
    const registers = document.getElementById("registers").children;
    let offset;
    
    /*
    new Uint8ClampedArray(
        instance.exports.memory.buffer,
        buffer_address,
        4 * width * height,
    ),
    const strBuf = new Uint8Array(instance.exports.memory.buffer, instance.getStrOffset(), 11);
    const value = new TextDecoder().decode(strBuf);
        const vMemory = new Uint8Array(
        exports.memory.buffer,
        exports.get_register_v(),
        16
    );
    */

    for (offset = 1; offset < registers.length; offset++) // Starting from 1 avoids renaming the legend.
        registers[offset].innerHTML = new TextDecoder().decode(new Uint32Array(memory.buffer)[offset]);
};