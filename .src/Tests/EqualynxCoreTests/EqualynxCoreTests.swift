import Testing
@testable import EqualynxCore

@Test func addReturnsSum() {
    #expect(add(2, 3) == 5)
}

@Test func parsesArithmeticEquationToTokens() throws {
    let json = try tokensJSON("3 + 5 = 8")
    #expect(json == """
    [{"id":0,"kind":"number","value":"3","tex":"3"},\
    {"id":1,"kind":"operator","value":"+","tex":"+"},\
    {"id":2,"kind":"number","value":"5","tex":"5"},\
    {"id":3,"kind":"equals","value":"=","tex":"="},\
    {"id":4,"kind":"number","value":"8","tex":"8"}]
    """)
}

@Test func multiplicationUsesTimesGlyph() throws {
    let json = try tokensJSON("6 * 7 = 42")
    #expect(json.contains("\"value\":\"\u{00D7}\",\"tex\":\"\\\\times\""))
    #expect(json.contains("\"value\":\"42\""))
}

@Test func bareExpressionHasNoEqualsToken() throws {
    let json = try tokensJSON("4 + 9")
    #expect(!json.contains("\"kind\":\"equals\""))
    #expect(json.contains("\"value\":\"4\""))
    #expect(json.contains("\"value\":\"9\""))
}

@Test func emptyInputYieldsEmptyArray() throws {
    #expect(try tokensJSON("") == "[]")
}

@Test func equationSplitsOnEquals() throws {
    let equation = try parseEquation("3 + 5 = 8")
    #expect(equation.lhs == .binary(.add, .number("3"), .number("5")))
    #expect(equation.rhs == .number("8"))
}

@Test func invalidInputThrows() {
    #expect(throws: ExpressionParserError.self) {
        _ = try tokensJSON("3 +")
    }
}

// Token ids for "3 + 5 = 8": 0=`3`, 1=`+`, 2=`5`, 3=`=`, 4=`8`.

@Test func combineCrossSideSubtractsTargetFromBothSides() throws {
    // Drop the answer 8 (id 4) onto the term 5 (id 2): eliminate the 5 -> 3 = 3.
    #expect(try combineEquation("3 + 5 = 8", draggedId: 4, targetId: 2) == "3 = 3")
}

@Test func combineSameSideMergesTerms() throws {
    // Drop 3 (id 0) onto 5 (id 2), both on the left: 3 + 5 -> 8, so 8 = 8.
    #expect(try combineEquation("3 + 5 = 8", draggedId: 0, targetId: 2) == "8 = 8")
}

@Test func combineCrossSideEliminatingTheAnswer() throws {
    // Drop 5 (id 2) onto 8 (id 4): subtract 8 from both -> 0 = 0.
    #expect(try combineEquation("3 + 5 = 8", draggedId: 2, targetId: 4) == "0 = 0")
}

@Test func combineRejectsOperatorToken() {
    #expect(throws: CombineError.self) {
        _ = try combineEquation("3 + 5 = 8", draggedId: 4, targetId: 1) // 1 is `+`
    }
}

@Test func combineRejectsBareExpression() {
    #expect(throws: CombineError.self) {
        _ = try combineEquation("3 + 5", draggedId: 0, targetId: 2)
    }
}

@Test func combineRejectsNonAdditiveEquation() {
    // "6 * 7 = 42": multiply isn't an additive term.
    #expect(throws: CombineError.self) {
        _ = try combineEquation("6 * 7 = 42", draggedId: 0, targetId: 2)
    }
}

// Linear equation moves. Token ids for "2x + 3 = 5": 0=`2`, 1=`x`, 2=`+`, 3=`3`,
// 4=`=`, 5=`5`. For "2x = 2": 0=`2`(coefficient), 1=`x`, 2=`=`, 3=`2`.

@Test func implicitMultiplyHidesOperatorAndGluesVariable() throws {
    let json = try tokensJSON("2x + 3 = 5")
    // No `×` between the coefficient and the variable...
    #expect(!json.contains("\"tex\":\"\\\\times\""))
    // ...and the variable token hugs the coefficient.
    #expect(json.contains("\"kind\":\"variable\",\"value\":\"x\",\"tex\":\"x\",\"glue\":true"))
}

@Test func linearMoveAddendAcrossByAdditiveInverse() throws {
    // Drag the addend 3 (id 3) onto 5: subtract 3 from both sides -> 2x = 2.
    #expect(try combineEquation("2x + 3 = 5", draggedId: 3, targetId: 5) == "2x = 2")
}

@Test func linearMoveMultiplicandAcrossByMultiplicativeInverse() throws {
    // Drag the multiplicand 2 (id 0) onto 2: divide both sides by 2 -> x = 1.
    #expect(try combineEquation("2x = 2", draggedId: 0, targetId: 3) == "x = 1")
}

@Test func linearFullSolvePathReachesGoal() throws {
    let step1 = try combineEquation("2x + 3 = 5", draggedId: 3, targetId: 5)
    #expect(step1 == "2x = 2")
    let step2 = try combineEquation(step1, draggedId: 0, targetId: 3)
    #expect(step2 == "x = 1")
}

@Test func linearDivideKeepsExactFraction() throws {
    // 2x = 3, divide by 2 -> x = 3/2 (no rounding).
    #expect(try combineEquation("2x = 3", draggedId: 0, targetId: 3) == "x = 3/2")
}

@Test func linearRejectsDroppingVariableTile() {
    // The `x` (id 1) isn't a draggable number — reject.
    #expect(throws: CombineError.self) {
        _ = try combineEquation("2x + 3 = 5", draggedId: 1, targetId: 5)
    }
}
