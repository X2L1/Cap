import Foundation
import JavaScriptCore

/// Small models are bad at arithmetic. Rather than hope the LLM counts right, we detect a
/// plain math expression in the user's message and compute it exactly, then hand the answer
/// to the model as authoritative context. Fully on-device, instant, and correct.
enum ArithmeticHelper {
    /// Returns "expr = value" if the message contains a simple arithmetic expression, else nil.
    static func computedHint(for message: String) -> String? {
        // Normalize common symbols, then keep only characters that belong in arithmetic.
        let normalized = message
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
        let mathScalars = normalized.unicodeScalars.filter {
            CharacterSet(charactersIn: "0123456789.+-*/() ").contains($0)
        }
        let expr = String(String.UnicodeScalarView(mathScalars)).trimmingCharacters(in: .whitespaces)

        // Require at least one operator and one digit, and balanced parentheses, so we don't
        // try to "evaluate" something that isn't really a calculation.
        guard expr.count >= 3,
              expr.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/")) != nil,
              expr.rangeOfCharacter(from: .decimalDigits) != nil,
              balancedParens(expr) else {
            return nil
        }

        // JavaScriptCore evaluates arithmetic safely (no NSException crash on bad input —
        // it just returns a non-number, which we reject). Input is already sanitized to math
        // characters only, so there's nothing executable beyond the calculation.
        guard let value = JSContext()?.evaluateScript(expr),
              value.isNumber else { return nil }
        let number = value.toDouble()
        guard number.isFinite else { return nil }

        let formatted = number == number.rounded()
            ? String(Int(number))
            : String(format: "%g", number)
        return "\(expr) = \(formatted)"
    }

    private static func balancedParens(_ s: String) -> Bool {
        var depth = 0
        for ch in s {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth -= 1 }
            if depth < 0 { return false }
        }
        return depth == 0
    }
}
