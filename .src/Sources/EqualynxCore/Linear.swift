/// First-order linear equation moves: solving `2x + 3 = 5` down to `x = 1` by
/// dragging tiles across the `=`.
///
/// Core rule — dragging a tile across the equals applies its **inverse** to both
/// sides, cancelling it on its own side:
///  - an **addend** moves by its *additive inverse* — subtract it from both sides
///    (`2x + 3 = 5`, drag 3 onto 5 → `2x = 2`).
///  - a **multiplicand** (a variable's coefficient) moves by its *multiplicative
///    inverse* — divide both sides by it (`2x = 2`, drag the 2 of 2x onto 2 → `x = 1`).
///
/// Each side is reduced to a linear form `a·x + b` with exact rational `a`, `b`, so
/// the divide step stays exact (`2 ÷ 2 = 1`, `3 ÷ 2 = 3/2`). Anything that isn't a
/// single-variable linear equation in whole-number terms is rejected as unsupported.

// MARK: - Exact rationals (wasm-safe: plain `Int`, `Int` interpolation only)

struct Ratio: Equatable {
    let num: Int
    let den: Int // always > 0

    init(_ numerator: Int, _ denominator: Int) {
        var n = numerator
        var d = denominator
        if d == 0 {
            d = 1 // guard; callers never divide by a zero denominator
        }
        if d < 0 {
            n = -n
            d = -d
        }
        let g = Ratio.gcd(n < 0 ? -n : n, d)
        if g > 1 {
            n = n / g
            d = d / g
        }
        num = n
        den = d
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 {
            let t = x % y
            x = y
            y = t
        }
        return x == 0 ? 1 : x
    }

    static let zero = Ratio(0, 1)

    var isZero: Bool { num == 0 }
    var isNegative: Bool { num < 0 }
    var isOne: Bool { num == 1 && den == 1 }
    var magnitude: Ratio { Ratio(num < 0 ? -num : num, den) }

    func plus(_ other: Ratio) -> Ratio {
        Ratio(num * other.den + other.num * den, den * other.den)
    }

    func minus(_ other: Ratio) -> Ratio {
        Ratio(num * other.den - other.num * den, den * other.den)
    }

    func dividedBy(_ other: Ratio) -> Ratio {
        Ratio(num * other.den, den * other.num)
    }

    /// `"3"`, `"-2"`, `"3/2"`. Plain `Int` interpolation only — wasm-safe.
    var text: String {
        if den == 1 {
            return "\(num)"
        }
        return "\(num)/\(den)"
    }
}

// MARK: - Linear form of one side: coefficient·variable + constant

struct LinearForm {
    var coefficient = Ratio.zero
    var variable: String?
    var constant = Ratio.zero

    func dividedBy(_ divisor: Ratio) -> LinearForm {
        var form = self
        form.coefficient = coefficient.dividedBy(divisor)
        form.constant = constant.dividedBy(divisor)
        return form
    }
}

/// What a single display token is, so a dropped tile's id maps to an algebraic role.
enum TokenRole {
    case constant(side: Int, value: Ratio)               // a loose ± number
    case coefficient(side: Int, value: Ratio, variable: String) // the number in `2x`
    case variable(side: Int, coefficient: Ratio, variable: String) // the `x`
    case other                                              // operator / equals
}

// MARK: - Combine on a linear equation

func combineLinear(_ equation: Equation, draggedId: Int, targetSide: Int) throws -> String {
    guard let rhs = equation.rhs else {
        throw CombineError.notAnEquation
    }

    var leftForm = LinearForm()
    var rightForm = LinearForm()
    var roles: [TokenRole] = []
    var id = 0

    // Walk both sides exactly as buildTokens emits tokens, so `roles[id]` lines up
    // with the ids the browser rendered.
    guard walkAdditive(equation.lhs, sign: 1, side: 0, id: &id, form: &leftForm, roles: &roles) else {
        throw CombineError.unsupported
    }
    roles.append(.other) // the `=`
    id += 1
    guard walkAdditive(rhs, sign: 1, side: 1, id: &id, form: &rightForm, roles: &roles) else {
        throw CombineError.unsupported
    }

    guard draggedId >= 0, draggedId < roles.count,
          targetSide == 0 || targetSide == 1 else {
        throw CombineError.invalidToken
    }

    let dragged = roles[draggedId]

    switch dragged {
    case let .constant(draggedSide, value):
        if targetSide == draggedSide {
            // Same side, both loose constants → merge them (render collapses to the sum).
            // (We just return the form, it inherently merges all constants on its side).
            return render(leftForm, rightForm)
        }
        // Addend moved across: add its additive inverse to both sides (i.e. subtract
        // it), cancelling it on its own side.
        leftForm.constant = leftForm.constant.minus(value)
        rightForm.constant = rightForm.constant.minus(value)
        return render(leftForm, rightForm)

    case let .coefficient(draggedSide, value, _):
        guard targetSide != draggedSide else {
            throw CombineError.unsupported
        }
        guard !value.isZero else {
            throw CombineError.unsupported
        }
        // Multiplicand moved across: multiply both sides by its multiplicative inverse
        // (i.e. divide by it), cancelling it on its own side and isolating the variable.
        return render(leftForm.dividedBy(value), rightForm.dividedBy(value))

    case let .variable(draggedSide, coefficient, variableName):
        if targetSide == draggedSide {
            return render(leftForm, rightForm)
        }
        // Variable term moved across: add its additive inverse to both sides
        leftForm.coefficient = leftForm.coefficient.minus(coefficient)
        leftForm.variable = variableName
        rightForm.coefficient = rightForm.coefficient.minus(coefficient)
        rightForm.variable = variableName
        return render(leftForm, rightForm)

    default:
        throw CombineError.invalidToken
    }
}

private func side(of role: TokenRole) -> Int? {
    switch role {
    case let .constant(side, _):
        return side
    case let .coefficient(side, _, _):
        return side
    case let .variable(side, _, _):
        return side
    case .other:
        return nil
    }
}

// MARK: - AST walk (mirrors TokenList.appendTokens emission order)

/// Walk an additive chain, threading the running sign and emitting one role per
/// token in the same order `appendTokens` produces them. Returns false if the side
/// isn't a whole-number single-variable linear expression.
private func walkAdditive(_ expression: Expression, sign: Int, side: Int, id: inout Int, form: inout LinearForm, roles: inout [TokenRole]) -> Bool {
    switch expression {
    case let .binary(.add, lhs, rhs):
        if !walkAdditive(lhs, sign: sign, side: side, id: &id, form: &form, roles: &roles) {
            return false
        }
        roles.append(.other) // the `+`
        id += 1
        return walkAdditive(rhs, sign: sign, side: side, id: &id, form: &form, roles: &roles)
    case let .binary(.subtract, lhs, rhs):
        if !walkAdditive(lhs, sign: sign, side: side, id: &id, form: &form, roles: &roles) {
            return false
        }
        roles.append(.other) // the `-`
        id += 1
        return walkAdditive(rhs, sign: -sign, side: side, id: &id, form: &form, roles: &roles)
    case let .unary(op, operand):
        roles.append(.other) // the unary `+`/`-`
        id += 1
        let nextSign = op == .minus ? -sign : sign
        return walkAdditive(operand, sign: nextSign, side: side, id: &id, form: &form, roles: &roles)
    default:
        return walkTerm(expression, sign: sign, side: side, id: &id, form: &form, roles: &roles)
    }
}

/// A single multiplicative term: a number, a variable, or coefficient × variable.
private func walkTerm(_ expression: Expression, sign: Int, side: Int, id: inout Int, form: inout LinearForm, roles: inout [TokenRole]) -> Bool {
    switch expression {
    case let .number(text):
        guard let n = wholeInt(text) else {
            return false
        }
        let value = Ratio(sign * n, 1)
        form.constant = form.constant.plus(value)
        roles.append(.constant(side: side, value: value))
        id += 1
        return true

    case let .variable(name):
        let coefficient = Ratio(sign, 1)
        form.coefficient = form.coefficient.plus(coefficient)
        form.variable = name
        roles.append(.variable(side: side, coefficient: coefficient, variable: name))
        id += 1
        return true

    case let .binary(op, lhs, rhs):
        if op == .divide {
            if case let .number(numText) = lhs, case let .number(denText) = rhs,
               let n = wholeInt(numText), let d = wholeInt(denText) {
                let value = Ratio(sign * n, d)
                form.constant = form.constant.plus(value)
                roles.append(.constant(side: side, value: value))
                id += 1
                return true
            }
            return false
        }
        
        guard op == .implicitMultiply || op == .multiply else {
            return false
        }
        // coefficient × variable, in either written order.
        if extractRatio(from: lhs) != nil, case let .variable(name) = rhs {
            return appendCoefficientTimesVariable(numberNode: lhs, name: name, numberFirst: true, explicit: op == .multiply, sign: sign, side: side, id: &id, form: &form, roles: &roles)
        }
        if case let .variable(name) = lhs, extractRatio(from: rhs) != nil {
            return appendCoefficientTimesVariable(numberNode: rhs, name: name, numberFirst: false, explicit: op == .multiply, sign: sign, side: side, id: &id, form: &form, roles: &roles)
        }
        return false

    default:
        return false
    }
}

private func extractRatio(from expression: Expression) -> Ratio? {
    if case let .number(text) = expression {
        guard let n = wholeInt(text) else { return nil }
        return Ratio(n, 1)
    }
    if case let .binary(.divide, numExpr, denExpr) = expression,
       case let .number(numText) = numExpr, case let .number(denText) = denExpr,
       let n = wholeInt(numText), let d = wholeInt(denText) {
        return Ratio(n, d)
    }
    return nil
}

private func appendCoefficientTimesVariable(numberNode: Expression, name: String, numberFirst: Bool, explicit: Bool, sign: Int, side: Int, id: inout Int, form: inout LinearForm, roles: inout [TokenRole]) -> Bool {
    guard let ratio = extractRatio(from: numberNode) else {
        return false
    }
    let coefficient = Ratio(sign * ratio.num, ratio.den)
    form.coefficient = form.coefficient.plus(coefficient)
    form.variable = name

    let coefficientRole = TokenRole.coefficient(side: side, value: coefficient, variable: name)
    let variableRole = TokenRole.variable(side: side, coefficient: coefficient, variable: name)

    if numberFirst {
        roles.append(coefficientRole)
        id += 1
        if explicit {
            roles.append(.other) // the `×`
            id += 1
        }
        roles.append(variableRole)
        id += 1
    } else {
        roles.append(variableRole)
        id += 1
        if explicit {
            roles.append(.other)
            id += 1
        }
        roles.append(coefficientRole)
        id += 1
    }
    return true
}

/// Parse a whole-number token string to `Int`, bounded to ±Int32.max so host and
/// wasm agree. Returns nil for decimals or out-of-range values.
private func wholeInt(_ text: String) -> Int? {
    guard let value = Int(text) else {
        return nil
    }
    if value > 2_147_483_647 || value < -2_147_483_647 {
        return nil
    }
    return value
}

// MARK: - Rendering a linear equation back to a re-parseable string

private func render(_ left: LinearForm, _ right: LinearForm) -> String {
    renderLinear(left) + " = " + renderLinear(right)
}

func renderLinear(_ form: LinearForm) -> String {
    let hasVariable = form.variable != nil && !form.coefficient.isZero
    if !hasVariable {
        return form.constant.text
    }

    var text = ""
    if form.coefficient.isNegative {
        text += "-"
    }
    let magnitude = form.coefficient.magnitude
    if !magnitude.isOne {
        text += magnitude.text
    }
    text += form.variable ?? "x"

    if !form.constant.isZero {
        if form.constant.isNegative {
            text += " - " + form.constant.magnitude.text
        } else {
            text += " + " + form.constant.text
        }
    }
    return text
}
