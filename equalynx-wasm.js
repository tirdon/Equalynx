/*
 * Equalynx — WASM bridge.
 *
 * Loads the Swift-compiled math engine (Engine.wasm) and drives the manual memory
 * protocol: allocate input bytes, call an export, read the result pointer + length,
 * decode, free. Mirrors GradGame's gradgame-wasm.js. Exposes:
 *   window.Equalynx.ready       — promise that resolves once the module is live
 *   window.Equalynx.parse(str)  — parse an equation string -> token array
 */
(function () {
  "use strict";

  const WASM_URL = "Engine.wasm";
  const OK = 0;
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  let exports = null;
  let memory = null;

  // Minimal WASI preview1 stub — the engine only needs benign no-ops plus a real
  // random_get. (Same surface the Node verification harness uses.)
  function wasiStub() {
    const writeZeros = (a, b) => {
      const dv = new DataView(memory.buffer);
      dv.setUint32(a, 0, true);
      dv.setUint32(b, 0, true);
      return OK;
    };
    return {
      args_get: () => OK,
      args_sizes_get: writeZeros,
      environ_get: () => OK,
      environ_sizes_get: writeZeros,
      fd_close: () => OK,
      fd_fdstat_get: () => OK,
      fd_prestat_dir_name: () => 8, // EBADF
      fd_prestat_get: () => 8, // EBADF
      fd_read: () => OK,
      fd_seek: () => OK,
      fd_write: (fd, iovsPtr, iovsLen, nwrittenPtr) => {
        const dv = new DataView(memory.buffer);
        let written = 0;
        for (let i = 0; i < iovsLen; i++) {
          written += dv.getUint32(iovsPtr + i * 8 + 4, true);
        }
        dv.setUint32(nwrittenPtr, written, true);
        return OK;
      },
      path_open: () => 8, // EBADF
      proc_exit: (code) => {
        throw new Error("wasm proc_exit(" + code + ")");
      },
      random_get: (ptr, len) => {
        crypto.getRandomValues(new Uint8Array(memory.buffer, ptr, len));
        return OK;
      },
    };
  }

  async function instantiate() {
    const imports = { wasi_snapshot_preview1: wasiStub() };
    let instance;
    try {
      const response = await fetch(WASM_URL);
      ({ instance } = await WebAssembly.instantiateStreaming(response, imports));
    } catch (streamErr) {
      // Fallback when the server doesn't send application/wasm.
      const buffer = await (await fetch(WASM_URL)).arrayBuffer();
      ({ instance } = await WebAssembly.instantiate(buffer, imports));
    }

    exports = instance.exports;
    memory = exports.memory;

    const smoke = exports.add(2, 3);
    if (smoke !== 5) {
      throw new Error("Engine smoke test failed: add(2, 3) = " + smoke);
    }
    console.log("[Equalynx] Engine.wasm ready — add(2, 3) =", smoke);
    return api;
  }

  // Parse an equation string into the token array produced by equalynxParseToTokens.
  function parse(input) {
    if (!exports) {
      throw new Error("Engine not ready");
    }
    const bytes = encoder.encode(input);
    const byteLen = bytes.length;
    const inputPtr = exports.equalynxAllocate(byteLen || 1);
    if (byteLen > 0) {
      new Uint8Array(memory.buffer, inputPtr, byteLen).set(bytes);
    }

    let text = "";
    let ok = false;
    try {
      const resultPtr = exports.equalynxParseToTokens(inputPtr, byteLen);
      const len = exports.equalynxLastResultLength();
      ok = exports.equalynxLastParseSucceeded() === 1;
      if (len > 0 && resultPtr) {
        // Decode (copies into a JS string) before freeing the wasm buffer.
        text = decoder.decode(new Uint8Array(memory.buffer, resultPtr, len));
      }
    } finally {
      exports.equalynxDeallocate(inputPtr, byteLen);
      exports.equalynxFreeLastResult();
    }

    if (!ok) {
      throw new Error(text || "Could not parse equation");
    }
    return JSON.parse(text || "[]");
  }

  // Apply a combine move: drop number token `draggedId` onto `targetId`. Returns
  // { ok, text } where text is the new equation string ("3 = 3") or a reason.
  function combine(input, draggedId, targetId) {
    if (!exports) {
      throw new Error("Engine not ready");
    }
    const bytes = encoder.encode(input);
    const byteLen = bytes.length;
    const inputPtr = exports.equalynxAllocate(byteLen || 1);
    if (byteLen > 0) {
      new Uint8Array(memory.buffer, inputPtr, byteLen).set(bytes);
    }

    let text = "";
    let ok = false;
    try {
      const resultPtr = exports.equalynxCombine(inputPtr, byteLen, draggedId, targetId);
      const len = exports.equalynxLastResultLength();
      ok = exports.equalynxLastParseSucceeded() === 1;
      if (len > 0 && resultPtr) {
        text = decoder.decode(new Uint8Array(memory.buffer, resultPtr, len));
      }
    } finally {
      exports.equalynxDeallocate(inputPtr, byteLen);
      exports.equalynxFreeLastResult();
    }
    return { ok: ok, text: text };
  }

  const api = { parse, combine };
  window.Equalynx = api;
  api.ready = instantiate();
})();
