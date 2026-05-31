#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct EngineMain {
    static func main() {
    }
}

// MARK: - Smoke test

/// Trivial FFI sanity check. The frontend calls `add(2, 3)` on boot; a clean `5`
/// proves the instance loaded and the C ABI bridge works before any real call.
@_expose(wasm, "add")
@_cdecl("add")
public func add(_ lhs: Int32, _ rhs: Int32) -> Int32 {
    lhs + rhs
}

// MARK: - Result handoff state

// The browser cannot read a Swift `String` directly, so every text-returning
// export stashes its bytes here and returns a pointer; JS reads the length, then
// decodes and frees. (`nonisolated(unsafe)` because wasm is single-threaded.)
nonisolated(unsafe) var lastResultPointer: UnsafeMutableRawPointer?
nonisolated(unsafe) var lastResultLength: Int32 = 0
nonisolated(unsafe) var lastParseSucceeded: Int32 = 0

// MARK: - Memory protocol

@_expose(wasm, "equalynxAllocate")
@_cdecl("equalynxAllocate")
public func equalynxAllocate(_ byteCount: Int32) -> UnsafeMutableRawPointer? {
    guard byteCount > 0 else {
        return nil
    }
    return UnsafeMutableRawPointer.allocate(byteCount: Int(byteCount), alignment: 1)
}

@_expose(wasm, "equalynxDeallocate")
@_cdecl("equalynxDeallocate")
public func equalynxDeallocate(_ pointer: UnsafeMutableRawPointer?, _ byteCount: Int32) {
    pointer?.deallocate()
}

@_expose(wasm, "equalynxLastResultLength")
@_cdecl("equalynxLastResultLength")
public func equalynxLastResultLength() -> Int32 {
    lastResultLength
}

@_expose(wasm, "equalynxLastParseSucceeded")
@_cdecl("equalynxLastParseSucceeded")
public func equalynxLastParseSucceeded() -> Int32 {
    lastParseSucceeded
}

@_expose(wasm, "equalynxFreeLastResult")
@_cdecl("equalynxFreeLastResult")
public func equalynxFreeLastResult() {
    lastResultPointer?.deallocate()
    lastResultPointer = nil
    lastResultLength = 0
}

// MARK: - Result helpers

/// Copies `bytes` into a freshly allocated byte-aligned buffer for handing across
/// the wasm FFI boundary. The caller owns the returned pointer and must free it.
func copyToWasmBuffer(_ bytes: [UInt8]) -> UnsafeMutableRawPointer {
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: bytes.count, alignment: 1)
    bytes.withUnsafeBytes { source in
        if let baseAddress = source.baseAddress {
            pointer.copyMemory(from: baseAddress, byteCount: bytes.count)
        }
    }
    return pointer
}

/// Stash `value` as the module-global result and return a pointer to its bytes.
/// `succeeded` flags whether the caller produced a real result or an error string.
func storeResult(_ value: String, succeeded: Bool) -> UnsafePointer<UInt8>? {
    equalynxFreeLastResult()

    let bytes = Array(value.utf8)
    lastResultLength = Int32(bytes.count)
    lastParseSucceeded = succeeded ? 1 : 0

    guard !bytes.isEmpty else {
        return nil
    }

    let pointer = copyToWasmBuffer(bytes)
    lastResultPointer = pointer
    return UnsafePointer(pointer.assumingMemoryBound(to: UInt8.self))
}
