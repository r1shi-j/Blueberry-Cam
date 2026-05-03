import Foundation

extension Float {
    var signedSingleDecimalString: String {
        let magnitude = abs(Double(self)).formatted(.number.precision(.fractionLength(1)))
        return self >= 0 ? "+\(magnitude)" : "-\(magnitude)"
    }
}
