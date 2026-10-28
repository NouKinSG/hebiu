import Foundation
import Testing
@testable import HebiuKit

@Suite struct WeatherTests {
    private let geo = #"{"results":[{"name":"上海","latitude":31.22,"longitude":121.46}]}"#
    private let forecast = #"{"current":{"temperature_2m":17.2,"weather_code":0},"daily":{"weather_code":[61,2],"temperature_2m_max":[22.7,21.1],"temperature_2m_min":[6.5,13.7],"precipitation_probability_max":[70,4]}}"#

    @Test func 查城市再查天气_解析_缓存一小时() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("weather-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var calls: [String] = []
        let client = WeatherClient(cacheURL: url) { u in
            calls.append(u.host ?? "")
            return Data((u.host!.hasPrefix("geocoding") ? geo : forecast).utf8)
        }
        let now = date("2026-10-26 08:00")
        let r = await client.report(city: "上海", now: now)
        #expect(r?.line == "☀️ 上海 17° · 今天 7～23° · 降雨 70%")
        #expect(r?.advice == ["今天可能下雨，记得带伞", "早晚很冷，多穿点", "早晚温差大"])
        #expect(r?.promptText.contains("明天多云") == true)
        #expect(calls.count == 2)
        _ = await client.report(city: "上海", now: date("2026-10-26 08:30"))
        #expect(calls.count == 2)                                  // 一小时内用缓存
        #expect(WeatherClient(cacheURL: url) { _ in Data() }.fresh(city: "上海", now: date("2026-10-26 08:40"))?.temp == 17.2)
        #expect(await client.report(city: "  ", now: now) == nil)
    }

    @Test func 网络失败用旧的_城市不对返回空() async {
        let client = WeatherClient(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID().uuidString)")) { _ in
            Data(#"{"results":[]}"#.utf8)
        }
        #expect(await client.report(city: "不存在的地方") == nil)
        #expect(WeatherReport.describe(95).text == "雷雨")
    }
}
