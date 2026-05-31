#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(Glibc)
import Glibc
#endif

/// Parse `(ptr, len)` UTF-8 as an equation and return a pointer to a JSON token
/// array (see `tokensJSON`). On any parse error, returns the error description with
/// the success flag cleared. The caller reads `equalynxLastResultLength()` /
/// `equalynxLastParseSucceeded()`, decodes, then frees with `equalynxFreeLastResult()`.
@_expose(wasm, "equalynxParseToTokens")
@_cdecl("equalynxParseToTokens")
public func equalynxParseToTokens(_ inputPointer: UnsafePointer<UInt8>?, _ inputLength: Int32) -> UnsafePointer<UInt8>? {
    let input: String
    if inputLength <= 0 {
        return storeResult("[]", succeeded: true)
    } else if let inputPointer {
        let inputBytes = UnsafeBufferPointer(start: inputPointer, count: Int(inputLength))
        input = String(decoding: inputBytes, as: UTF8.self)
    } else {
        return storeResult("Input pointer is missing.", succeeded: false)
    }

    do {
        return storeResult(try tokensJSON(input), succeeded: true)
    } catch let error as ExpressionParserError {
        return storeResult(error.description, succeeded: false)
    } catch {
        return storeResult("Unable to parse equation.", succeeded: false)
    }
}

/// Apply a combine move (drop number token `draggedId` onto `targetId`) to the
/// equation at `(ptr, len)`. Returns the resulting equation string ("3 = 3") on
/// success, or the failure reason with the success flag cleared. Same read/free
/// protocol as `equalynxParseToTokens`.
@_expose(wasm, "equalynxCombine")
@_cdecl("equalynxCombine")
public func equalynxCombine(
    _ inputPointer: UnsafePointer<UInt8>?,
    _ inputLength: Int32,
    _ draggedId: Int32,
    _ targetId: Int32
) -> UnsafePointer<UInt8>? {
    guard inputLength > 0, let inputPointer else {
        return storeResult("No equation to combine.", succeeded: false)
    }
    let inputBytes = UnsafeBufferPointer(start: inputPointer, count: Int(inputLength))
    let input = String(decoding: inputBytes, as: UTF8.self)

    do {
        let result = try combineEquation(input, draggedId: Int(draggedId), targetId: Int(targetId))
        return storeResult(result, succeeded: true)
    } catch let error as CombineError {
        return storeResult(error.description, succeeded: false)
    } catch let error as ExpressionParserError {
        return storeResult(error.description, succeeded: false)
    } catch {
        return storeResult("Could not combine tiles.", succeeded: false)
    }
}
