/// Per-token TeX math source. Tokens are rendered to SVG individually in the
/// browser (one MathJax render per glyph) so each becomes its own draggable group —
/// hence this maps a single atom/operator to its TeX markup, not a whole equation.
enum TeXGlyph {
    /// A binary operator's display symbol and its TeX math source.
    static func binary(_ op: BinaryOperator) -> (value: String, tex: String) {
        switch op {
        case .add:
            return ("+", "+")
        case .subtract:
            return ("\u{2212}", "-") // − (minus sign) for display, ASCII '-' for TeX
        case .multiply, .implicitMultiply:
            return ("\u{00D7}", "\\times") // ×
        case .divide:
            return ("\u{00F7}", "\\div") // ÷
        case .power:
            return ("^", "\\hat{\\ }") // unreached in the arithmetic slice
        }
    }

    static func unary(_ op: UnaryOperator) -> (value: String, tex: String) {
        switch op {
        case .plus:
            return ("+", "+")
        case .minus:
            return ("\u{2212}", "-")
        }
    }

    static func variable(_ name: String) -> String {
        switch name {
        case "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta",
             "iota", "kappa", "lambda", "mu", "nu", "xi", "omicron", "pi", "rho",
             "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega",
             "Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta",
             "Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi", "Rho",
             "Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega":
            return "\\" + name
        default:
            return name
        }
    }

    static func constant(_ name: String) -> String {
        switch name {
        case "pi":
            return "\\pi"
        case "phi":
            return "\\phi"
        case "gamma":
            return "\\gamma"
        default:
            return name
        }
    }

    static let equals = (value: "=", tex: "=")
}
