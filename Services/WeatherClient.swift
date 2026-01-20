//
//  WeatherClient.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import Foundation

protocol WeatherClient {
    func hourly(lat: Double, lon: Double, startISO: String, endISO: String) async throws -> [WxFeature]
    
    // 現在の天気を取得
    func currentWeather(lat: Double, lon: Double) async throws -> WxFeature?
    
    // 日別予報を取得
    func dailyForecast(lat: Double, lon: Double, days: Int) async throws -> [DailyWeather]
}

struct DailyWeather {
    let date: Date
    let maxTemp: Double
    let minTemp: Double
    let icon: WeatherIcon
}

actor WeatherCache {
    struct Entry: Codable {
        let fetchedAt: Date
        let data: [WxFeature]
    }

    private struct CacheFile: Codable {
        let entries: [String: Entry]
    }

    private var storage: [String: Entry] = [:]
    private let ttl: TimeInterval = 12 * 60 * 60
    private let fileURL: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        fileURL = (caches ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("weather_cache.json")
        storage = Self.loadFromDisk(fileURL: fileURL)
    }

    func get(_ key: String) -> [WxFeature]? {
        guard let entry = storage[key] else { return nil }
        if Date().timeIntervalSince(entry.fetchedAt) > ttl {
            return nil
        }
        return entry.data
    }

    func getStaleWithin(_ key: String, maxAge: TimeInterval) -> [WxFeature]? {
        guard let entry = storage[key] else { return nil }
        if Date().timeIntervalSince(entry.fetchedAt) > maxAge {
            return nil
        }
        return entry.data
    }

    func set(_ key: String, data: [WxFeature]) {
        storage[key] = Entry(fetchedAt: Date(), data: data)
        persist()
    }

    private func persist() {
        let payload = CacheFile(entries: storage)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    private static func loadFromDisk(fileURL: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(CacheFile.self, from: data) else {
            return [:]
        }
        return payload.entries
    }
}

final class OpenMeteoClient: WeatherClient {
    private static let cache = WeatherCache()

    func hourly(lat: Double, lon: Double, startISO: String, endISO: String) async throws -> [WxFeature] {
        let key = cacheKey(lat: lat, lon: lon, startISO: startISO, endISO: endISO)
        if let cached = await Self.cache.get(key) {
            return cached
        }

        // UTCで指定（簡易）。JST→UTC変換はDateFormatterで。
        let params = [
            "latitude": "\(lat)",
            "longitude": "\(lon)",
            "hourly": "precipitation,temperature_2m,apparent_temperature,visibility,windspeed_10m,showers",
            "start": startISO,
            "end": endISO,
            "timezone": "UTC"
        ]
        let qs = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?\(qs)")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // 返却を必要最低限でパース
            struct Res: Decodable {
                struct Hourly: Decodable {
                    let time: [String]
                    let precipitation: [Double]
                    let windspeed_10m: [Double]
                    let apparent_temperature: [Double]
                    let visibility: [Double]
                    let showers: [Double]?
                    let temperature_2m: [Double]?
                }
                let hourly: Hourly
            }
            let r = try JSONDecoder().decode(Res.self, from: data)
            let count = [
                r.hourly.time.count,
                r.hourly.precipitation.count,
                r.hourly.windspeed_10m.count,
                r.hourly.apparent_temperature.count,
                r.hourly.visibility.count
            ].min() ?? 0
            var arr: [WxFeature] = []
            for i in 0..<count {
                arr.append(WxFeature(
                    timeISO: r.hourly.time[i],
                    rain: max(r.hourly.precipitation[i], (r.hourly.showers?[i] ?? 0)),
                    wind: r.hourly.windspeed_10m[i] / 3.6, // km/h→m/s換算ならここで
                    feels: r.hourly.apparent_temperature[i],
                    visibility: r.hourly.visibility[i] / 1000.0, // m→km
                    thunder: false // MVPでは未判定（将来拡張）
                ))
            }
            await Self.cache.set(key, data: arr)
            return arr
        } catch {
            if let fallback = await Self.cache.getStaleWithin(key, maxAge: 12 * 60 * 60) {
                return fallback
            }
            throw error
        }
    }
    
    func currentWeather(lat: Double, lon: Double) async throws -> WxFeature? {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startISO = formatter.string(from: now)
        let endISO = formatter.string(from: endDate)
        
        let hourly = try await hourly(lat: lat, lon: lon, startISO: startISO, endISO: endISO)
        return hourly.first
    }
    
    func dailyForecast(lat: Double, lon: Double, days: Int) async throws -> [DailyWeather] {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: now)!
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startISO = formatter.string(from: now)
        let endISO = formatter.string(from: endDate)
        
        let hourly = try await hourly(lat: lat, lon: lon, startISO: startISO, endISO: endISO)
        
        // 日別にグループ化
        var dailyMap: [String: [WxFeature]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for wx in hourly {
            guard let date = parseISO8601(wx.timeISO) else { continue }
            let dayKey = dateFormatter.string(from: date)
            
            if dailyMap[dayKey] == nil {
                dailyMap[dayKey] = []
            }
            dailyMap[dayKey]?.append(wx)
        }
        
        // 各日の代表的な天気を作成
        var dailyWeathers: [DailyWeather] = []
        let sortedKeys = dailyMap.keys.sorted()
        
        for key in sortedKeys {
            guard let weathers = dailyMap[key],
                  let firstDate = parseISO8601(weathers.first?.timeISO ?? ""),
                  let firstWeather = weathers.first else { continue }
            
            // 今日より前の日付は除外
            let today = Calendar.current.startOfDay(for: Date())
            if firstDate < today {
                continue
            }
            
            let maxTemp = weathers.map { $0.feels }.max() ?? firstWeather.feels
            let minTemp = weathers.map { $0.feels }.min() ?? firstWeather.feels
            let icon = weatherIcon(for: firstWeather)
            
            dailyWeathers.append(DailyWeather(
                date: firstDate,
                maxTemp: maxTemp,
                minTemp: minTemp,
                icon: icon
            ))
        }
        
        return dailyWeathers
    }
    
    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? {
            let formatter2 = ISO8601DateFormatter()
            formatter2.formatOptions = [.withInternetDateTime]
            return formatter2.date(from: string)
        }()
    }

    private func cacheKey(lat: Double, lon: Double, startISO: String, endISO: String) -> String {
        let precision = 0.01
        let latKey = (lat / precision).rounded() * precision
        let lonKey = (lon / precision).rounded() * precision
        return "\(latKey),\(lonKey),\(startISO),\(endISO)"
    }
}
