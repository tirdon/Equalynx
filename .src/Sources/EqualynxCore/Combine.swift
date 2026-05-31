/// The "combine" move: the player drops one number token onto another.
///
///  - Same side  → merge the two terms into their sum (`3 + 5 = 8`, drop 3 on 5 → `8 = 8`).
///  - Cross side → subtract the *target* term from both sides and fold each side to a single
///    number (`3 + 5 = 8`, drop 8 on 5 → eliminate the 5 → `3 = 3`).
///
/// Scoped to the arithmetic slice: both sides must be whole numbers joined by `+`/`-`.
enum CombineError: Error, Equatable, CustomStringConvertible {
    case notAnEquation
    case unsupported
    case invalidToken

    var description: String {
        switch self {
        case .notAnEquation:
            return "Needs an equation with '='."
        case .unsupported:
            return "Combine supports whole-number additive terms only."
        case .invalidToken:
            return "Drop one number tile onto another."
        }
    }
}

/// Apply a combine to `input` and return the resulting equation string ("3 = 3").
func combineEquation(_ input: String, draggedId: Int, targetId: Int) throws -> String {
    if draggedId == targetId {
        throw CombineError.invalidToken
    }

    let equation = try parseEquation(input)
    guard let rhs = equation.rhs else {
        throw CombineError.notAnEquation
    }

    // Pure whole-number arithmetic on both sides → the original combine. Otherwise
    // (a side carries a variable) hand off to the linear-equation moves.
    guard let left = flattenAdditive(equation.lhs),
          let right = flattenAdditive(rhs) else {
        return try combineLinear(equation, draggedId: draggedId, targetId: targetId)
    }

    // Number-token ids per side, taken from the same deterministic token list the
    // browser rendered. For additive integer sides each number is one term, so the
    // j-th number token on a side lines up with the j-th flattened value.
    let tokens = buildTokens(equation)
    var leftIds: [Int] = []
    var rightIds: [Int] = []
    var side = 0
    var i = 0
    while i < tokens.count {
        let token = tokens[i]
        if token.kind == "equals" {
            side = 1
        } else if token.kind == "number" {
            if side == 0 {
                leftIds.append(i)
            } else {
                rightIds.append(i)
            }
        }
        i += 1
    }

    guard leftIds.count == left.count, rightIds.count == right.count else {
        throw CombineError.unsupported
    }

    guard let dragged = locate(draggedId, leftIds: leftIds, rightIds: rightIds),
          let target = locate(targetId, leftIds: leftIds, rightIds: rightIds) else {
        throw CombineError.invalidToken
    }

    if dragged.side == target.side {
        // Same side: merge the two terms into their sum.
        let values = dragged.side == 0 ? left : right
        let merged = values[dragged.index] + values[target.index]
        let lo = min(dragged.index, target.index)
        let hi = max(dragged.index, target.index)

        var rebuilt: [Double] = []
        var k = 0
        while k < values.count {
            if k == lo {
                rebuilt.append(merged)
            } else if k != hi {
                rebuilt.append(values[k])
            }
            k += 1
        }

        return dragged.side == 0
            ? renderEquation(rebuilt, right)
            : renderEquation(left, rebuilt)
    }

    // Cross side: subtract the dropped-on term from both sides; fold each to one number.
    let targetValue = (target.side == 0 ? left : right)[target.index]
    let leftTotal = total(left) - targetValue
    let rightTotal = total(right) - targetValue
    return renderEquation([leftTotal], [rightTotal])
}

// MARK: - Helpers

/// Flatten an additive expression into signed whole-number terms, or nil if it
/// contains anything other than numbers joined by `+`/`-` (e.g. ×, ÷, variables).
private func flattenAdditive(_ expression: Expression) -> [Double]? {
    var values: [Double] = []
    if appendAdditive(expression, sign: 1.0, into: &values) {
        return values
    }
    return nil
}

private func appendAdditive(_ expression: Expression, sign: Double, into values: inout [Double]) -> Bool {
    switch expression {
    case let .number(text):
        guard let value = Double(text), value.rounded() == value else {
            return false
        }
        values.append(sign * value)
        return true
    case let .unary(op, operand):
        return appendAdditive(operand, sign: op == .minus ? -sign : sign, into: &values)
    case let .binary(op, lhs, rhs):
        switch op {
        case .add:
            return appendAdditive(lhs, sign: sign, into: &values)
                && appendAdditive(rhs, sign: sign, into: &values)
        case .subtract:
            return appendAdditive(lhs, sign: sign, into: &values)
                && appendAdditive(rhs, sign: -sign, into: &values)
        default:
            return false
        }
    default:
        return false
    }
}

private func locate(_ id: Int, leftIds: [Int], rightIds: [Int]) -> (side: Int, index: Int)? {
    var i = 0
    while i < leftIds.count {
        if leftIds[i] == id {
            return (0, i)
        }
        i += 1
    }
    i = 0
    while i < rightIds.count {
        if rightIds[i] == id {
            return (1, i)
        }
        i += 1
    }
    return nil
}

private func total(_ values: [Double]) -> Double {
    var sum = 0.0
    var i = 0
    while i < values.count {
        sum += values[i]
        i += 1
    }
    return sum
}

private func renderEquation(_ left: [Double], _ right: [Double]) -> String {
    renderSide(left) + " = " + renderSide(right)
}

private func renderSide(_ values: [Double]) -> String {
    if values.isEmpty {
        return "0"
    }
    var text = formatWhole(values[0])
    var i = 1
    while i < values.count {
        let value = values[i]
        if value < 0 {
            text += " - " + formatWhole(-value)
        } else {
            text += " + " + formatWhole(value)
        }
        i += 1
    }
    return text
}

/// Whole-number formatting via plain `Int` interpolation (wasm-safe, unlike `Int32`/Double).
private func formatWhole(_ value: Double) -> String {
    "\(Int(value.rounded()))"
}
