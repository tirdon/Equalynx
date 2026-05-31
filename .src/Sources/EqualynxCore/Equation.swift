/// An equation is two expressions joined by `=`. A bare expression (no `=`) parses
/// with `rhs == nil`. The lexer has no `=` token, so we split the raw input on the
/// first top-level `=` byte and parse each side independently — sufficient for the
/// arithmetic slice (no parenthesised relations yet).
struct Equation: Equatable {
    let lhs: Expression
    let rhs: Expression?
}

func parseEquation(_ input: String) throws -> Equation {
    let bytes = Array(input.utf8)

    var splitIndex = -1
    var i = 0
    while i < bytes.count {
        if bytes[i] == 61 { // '='
            splitIndex = i
            break
        }
        i += 1
    }

    if splitIndex < 0 {
        return Equation(lhs: try parseExpression(input), rhs: nil)
    }

    // Mirror the lexer's wasm-safe `String(decoding: slice, as: UTF8.self)` form
    // rather than building intermediate arrays.
    let left = String(decoding: bytes[0..<splitIndex], as: UTF8.self)
    let right = String(decoding: bytes[(splitIndex + 1)..<bytes.count], as: UTF8.self)
    return Equation(lhs: try parseExpression(left), rhs: try parseExpression(right))
}
