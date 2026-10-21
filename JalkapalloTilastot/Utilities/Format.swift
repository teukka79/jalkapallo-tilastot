import Foundation

enum Format {
    private static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fi_FI")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    private static let dayHeading: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fi_FI")
        f.dateFormat = "cccc d. MMMM"
        return f
    }()

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fi_FI")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 1,4
    static func one(_ value: Double) -> String {
        decimal.string(from: NSNumber(value: value)) ?? "–"
    }

    /// 38,5 %
    static func percent(_ value: Double) -> String { one(value) + " %" }

    /// lauantai 17. lokakuuta
    static func day(_ date: Date) -> String { dayHeading.string(from: date).capitalizedFirst }

    /// 18:30
    static func time(_ date: Date) -> String { clock.string(from: date) }
}

extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
