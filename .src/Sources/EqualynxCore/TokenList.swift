/// A single draggable display token. The frontend renders `tex` to its own SVG,
/// tags the element with `kind`/`value`, and lays tokens out left-to-right.
struct DisplayToken: Equatable {
    let kind: String   // "number" | "operator" | "equals" | "variable" | "constant"
    let value: String  // human-facing symbol, e.g. "3", "+", "×", "="
    let tex: String    // TeX math source for this one glyph
    var glue = false   // true → hug the previous token (juxtaposed, e.g. the x in 2x)
}

/// Walk an equation in left-to-right reading order into a flat token list. For the
/// arithmetic slice the AST is binary number arithmetic, so an in-order traversal
/// (left, operator, right) reproduces the written form. (Parenthesised sub-terms
/// would need precedence-aware grouping; out of scope for the slice.)
func buildTokens(_ equation: Equation) -> [DisplayToken] {
    var tokens: [DisplayToken] = []
    appendTokens(equation.lhs, into: &tokens)
    if let rhs = equation.rhs {
        tokens.append(DisplayToken(kind: "equals", value: TeXGlyph.equals.value, tex: TeXGlyph.equals.tex))
        appendTokens(rhs, into: &tokens)
    }
    return tokens
}

private func appendTokens(_ expression: Expression, into tokens: inout [DisplayToken]) {
    switch expression {
    case let .number(value):
        tokens.append(DisplayToken(kind: "number", value: value, tex: value))
    case let .variable(name):
        tokens.append(DisplayToken(kind: "variable", value: name, tex: TeXGlyph.variable(name)))
    case let .constant(name):
        tokens.append(DisplayToken(kind: "constant", value: name, tex: TeXGlyph.constant(name)))
    case let .unary(op, operand):
        let glyph = TeXGlyph.unary(op)
        tokens.append(DisplayToken(kind: "operator", value: glyph.value, tex: glyph.tex))
        appendTokens(operand, into: &tokens)
    case let .binary(op, lhs, rhs):
        if op == .implicitMultiply {
            // Juxtaposition (e.g. `2x`): no operator glyph; the right factor hugs the
            // left so the coefficient reads as attached to the variable.
            appendTokens(lhs, into: &tokens)
            let glueIndex = tokens.count
            appendTokens(rhs, into: &tokens)
            if glueIndex < tokens.count {
                tokens[glueIndex].glue = true
            }
        } else if op == .divide {
            let numTex = texString(for: lhs)
            let denTex = texString(for: rhs)
            let tex = "\\frac{\(numTex)}{\(denTex)}"
            let value = "\(valueString(for: lhs))/\(valueString(for: rhs))"
            tokens.append(DisplayToken(kind: "number", value: value, tex: tex))
        } else {
            appendTokens(lhs, into: &tokens)
            let glyph = TeXGlyph.binary(op)
            tokens.append(DisplayToken(kind: "operator", value: glyph.value, tex: glyph.tex))
            appendTokens(rhs, into: &tokens)
        }
    case .function, .derivative:
        // Not produced by the arithmetic slice.
        break
    }
}

private func texString(for expression: Expression) -> String {
    switch expression {
    case let .number(value): return value
    case let .variable(name): return TeXGlyph.variable(name)
    case let .constant(name): return TeXGlyph.constant(name)
    case let .unary(op, operand):
        return TeXGlyph.unary(op).tex + texString(for: operand)
    case let .binary(op, lhs, rhs):
        if op == .divide {
            return "\\frac{\(texString(for: lhs))}{\(texString(for: rhs))}"
        }
        return texString(for: lhs) + TeXGlyph.binary(op).tex + texString(for: rhs)
    default: return ""
    }
}

private func valueString(for expression: Expression) -> String {
    switch expression {
    case let .number(value): return value
    case let .variable(name): return name
    case let .constant(name): return name
    case let .unary(op, operand):
        return TeXGlyph.unary(op).value + valueString(for: operand)
    case let .binary(op, lhs, rhs):
        if op == .divide {
            return "\(valueString(for: lhs))/\(valueString(for: rhs))"
        }
        return valueString(for: lhs) + TeXGlyph.binary(op).value + valueString(for: rhs)
    default: return ""
    }
}

/// Parse `input` into the JSON token array the browser consumes, e.g.
/// `[{"id":0,"kind":"number","value":"3","tex":"3"}, ...]`. Built by string
/// concatenation only (token fields are already `String`s — no `Int32`
/// interpolation, which traps on wasm).
func tokensJSON(_ input: String) throws -> String {
    if isBlank(input) {
        return "[]"
    }
    let equation = try parseEquation(input)
    let tokens = buildTokens(equation)

    var json = "["
    var i = 0
    while i < tokens.count {
        if i > 0 {
            json += ","
        }
        let token = tokens[i]
        json += "{\"id\":\(i),\"kind\":\""
        json += jsonEscape(token.kind)
        json += "\",\"value\":\""
        json += jsonEscape(token.value)
        json += "\",\"tex\":\""
        json += jsonEscape(token.tex)
        json += "\""
        if token.glue {
            json += ",\"glue\":true"
        }
        json += "}"
        i += 1
    }
    json += "]"
    return json
}

/// True when `value` has no non-whitespace bytes.
private func isBlank(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    var i = 0
    while i < bytes.count {
        let byte = bytes[i]
        if byte != 32 && byte != 9 && byte != 10 && byte != 13 {
            return false
        }
        i += 1
    }
    return true
}

/// Minimal JSON string escaping. Works on raw UTF-8 bytes and decodes once at the
/// end so multi-byte symbols (× ÷ −) survive intact.
private func jsonEscape(_ value: String) -> String {
    let bytes = Array(value.utf8)
    var out: [UInt8] = []
    var i = 0
    while i < bytes.count {
        let byte = bytes[i]
        switch byte {
        case 34: // "
            out.append(92); out.append(34)
        case 92: // \
            out.append(92); out.append(92)
        case 10: // newline
            out.append(92); out.append(110)
        case 13: // carriage return
            out.append(92); out.append(114)
        case 9: // tab
            out.append(92); out.append(116)
        default:
            out.append(byte)
        }
        i += 1
    }
    return String(decoding: out, as: UTF8.self)
}
