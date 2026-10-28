import Foundation

/// 天气：Open-Meteo（免费，不要账号和 key）。只把城市名和经纬度发过去；不填城市就完全不联网
public struct WeatherReport: Codable, Equatable {
    public struct Day: Codable, Equatable {
        public var code: Int
        public var min: Double
        public var max: Double
        public var rain: Int            // 降雨概率 %
    }

    public var city: String
    public var temp: Double
    public var code: Int
    public var today: Day
    public var tomorrow: Day?
    public var fetchedAt: Date

    public var emoji: String { WeatherReport.describe(code).emoji }
    public var text: String { WeatherReport.describe(code).text }

    /// 「☀️ 上海 17° · 今天 16～23° · 降雨 0%」
    public var line: String {
        "\(emoji) \(city) \(Int(temp.rounded()))° · 今天 \(Int(today.min.rounded()))～\(Int(today.max.rounded()))°" + (today.rain > 0 ? " · 降雨 \(today.rain)%" : "")
    }

    /// 要提醒的：带伞、多穿、多喝水、温差大
    public var advice: [String] {
        var out: [String] = []
        if today.rain >= 50 || [61, 63, 65, 80, 81, 82, 95, 96, 99].contains(today.code) { out.append("今天可能下雨，记得带伞") }
        if today.min <= 8 { out.append("早晚很冷，多穿点") }
        if today.max >= 32 { out.append("今天很热，多喝水") }
        if today.max - today.min >= 10 { out.append("早晚温差大") }
        if let t = tomorrow, t.rain >= 60, today.rain < 50 { out.append("明天可能下雨") }
        return out
    }

    /// 给她的一段话（带进提示词）
    public var promptText: String {
        var s = "\(city)天气：现在 \(Int(temp.rounded()))°，\(text)；今天 \(Int(today.min.rounded()))～\(Int(today.max.rounded()))°，降雨概率 \(today.rain)%"
        if let t = tomorrow { s += "；明天\(WeatherReport.describe(t.code).text) \(Int(t.min.rounded()))～\(Int(t.max.rounded()))°，降雨概率 \(t.rain)%" }
        return s
    }

    /// WMO 天气代码 → 中文和图标
    public static func describe(_ code: Int) -> (text: String, emoji: String) {
        switch code {
        case 0: return ("晴", "☀️")
        case 1: return ("晴间多云", "🌤")
        case 2: return ("多云", "⛅️")
        case 3: return ("阴", "☁️")
        case 45, 48: return ("雾", "🌫")
        case 51, 53, 55, 56, 57: return ("毛毛雨", "🌦")
        case 61, 63, 80, 81: return ("雨", "🌧")
        case 65, 82: return ("大雨", "🌧")
        case 66, 67: return ("冻雨", "🌧")
        case 71, 73, 75, 77, 85, 86: return ("雪", "❄️")
        case 95, 96, 99: return ("雷雨", "⛈")
        default: return ("—", "🌡")
        }
    }
}

public final class WeatherClient {
    public typealias Fetch = (URL) async throws -> Data
    private let fetch: Fetch
    private let cacheURL: URL
    public private(set) var cached: WeatherReport?

    public init(cacheURL: URL = Paths.dataDir.appendingPathComponent("weather.json"),
                fetch: @escaping Fetch = { url in
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 15
                    return try await URLSession.shared.data(for: req).0
                }) {
        self.cacheURL = cacheURL
        self.fetch = fetch
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        cached = (try? Data(contentsOf: cacheURL)).flatMap { try? d.decode(WeatherReport.self, from: $0) }
    }

    /// 缓存还新鲜（同一个城市、一小时内）就不再请求
    public func fresh(city: String, now: Date = Date()) -> WeatherReport? {
        guard let c = cached, c.city == city, now.timeIntervalSince(c.fetchedAt) < 3600,
              Calendar.current.isDate(c.fetchedAt, inSameDayAs: now) else { return nil }
        return c
    }

    public func report(city: String, now: Date = Date()) async -> WeatherReport? {
        let city = city.trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else { return nil }
        if let f = fresh(city: city, now: now) { return f }
        do {
            var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            geo.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "zh")]
            let g = try JSONSerialization.jsonObject(with: try await fetch(geo.url!)) as? [String: Any]
            guard let place = (g?["results"] as? [[String: Any]])?.first,
                  let lat = place["latitude"] as? Double, let lon = place["longitude"] as? Double else {
                Log.write("weather: city not found")
                return nil
            }
            var f = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            f.queryItems = [
                .init(name: "latitude", value: String(format: "%.3f", lat)), .init(name: "longitude", value: String(format: "%.3f", lon)),
                .init(name: "current", value: "temperature_2m,weather_code"),
                .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
                .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "2"),
            ]
            guard let report = WeatherClient.parse(try await fetch(f.url!), city: city, now: now) else { return cached }
            cached = report
            let e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            if let data = try? e.encode(report) { try? data.write(to: cacheURL, options: .atomic) }
            return report
        } catch {
            Log.write("weather: \(error.localizedDescription)")
            return cached?.city == city ? cached : nil
        }
    }

    static func parse(_ data: Data, city: String, now: Date) -> WeatherReport? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = obj["current"] as? [String: Any], let daily = obj["daily"] as? [String: Any],
              let temp = (current["temperature_2m"] as? NSNumber)?.doubleValue,
              let code = (current["weather_code"] as? NSNumber)?.intValue else { return nil }
        func day(_ i: Int) -> WeatherReport.Day? {
            guard let codes = daily["weather_code"] as? [NSNumber], let mins = daily["temperature_2m_min"] as? [NSNumber],
                  let maxs = daily["temperature_2m_max"] as? [NSNumber], i < codes.count, i < mins.count, i < maxs.count else { return nil }
            let rain = (daily["precipitation_probability_max"] as? [Any])?[safe: i] as? NSNumber
            return .init(code: codes[i].intValue, min: mins[i].doubleValue, max: maxs[i].doubleValue, rain: rain?.intValue ?? 0)
        }
        guard let today = day(0) else { return nil }
        return WeatherReport(city: city, temp: temp, code: code, today: today, tomorrow: day(1), fetchedAt: now)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
