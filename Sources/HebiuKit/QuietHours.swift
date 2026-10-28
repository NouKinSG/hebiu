import Foundation

/// 安静时段：「12:00-13:30, 22:30-08:00」，跨午夜的也行。这段时间里她像开了勿扰一样
public struct QuietHours: Equatable {
    public struct Range: Equatable {
        public var start: Int       // 从 0 点算起的分钟
        public var end: Int
    }

    public var ranges: [Range]

    public init?(_ text: String) {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
        var out: [Range] = []
        for part in parts {
            let ends = part.split(whereSeparator: { $0 == "-" || $0 == "~" || $0 == "～" || $0 == "到" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard ends.count == 2, let a = QuietHours.minutes(ends[0]), let b = QuietHours.minutes(ends[1]), a != b else { return nil }
            out.append(Range(start: a, end: b))
        }
        guard !out.isEmpty else { return nil }
        ranges = out
    }

    public func contains(_ date: Date, calendar cal: Calendar = .current) -> Bool {
        let m = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        return ranges.contains { r in r.start < r.end ? (m >= r.start && m < r.end) : (m >= r.start || m < r.end) }
    }

    static func minutes(_ s: String) -> Int? {
        let p = s.split(whereSeparator: { $0 == ":" || $0 == "：" }).compactMap { Int($0) }
        guard let h = p.first, (0...24).contains(h) else { return nil }
        let m = p.count > 1 ? p[1] : 0
        guard (0...59).contains(m) else { return nil }
        return (h % 24) * 60 + m
    }
}
