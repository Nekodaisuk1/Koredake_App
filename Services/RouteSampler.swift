//
//  RouteSampler.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import Foundation

struct SegmentContext {
    let mode: Mode
    let rainAversion: Int // 0..2
    let start: Date
    let durationMin: Int
    let sampleLatLon: LatLng // MVPは中点固定でOK
}

final class SegmentEvaluator {
    let weather: WeatherClient
    let rules: RuleEngine
    let routeRisk: RouteRiskEvaluator
    
    init(weather: WeatherClient) {
        self.weather = weather
        let rules = RuleEngine()
        self.rules = rules
        self.routeRisk = RouteRiskEvaluator(weather: weather, rules: rules)
    }

    func evaluate(segment: Segment, rainAversion: Int, ydayWx: WxFeature?) async throws -> SegmentResult {
        let todayDate = dateForToday(timeString: segment.startTime)
        let start = todayDate
        let end = Calendar.current.date(byAdding: .minute, value: segment.durationMin + 30, to: start)!
        let targetArrival = segment.targetArrivalTime.map { dateForTodayOrNext(timeString: $0, reference: start) }

        if let from = segment.latLngFrom, let to = segment.latLngTo {
            if let summary = try? await routeRisk.evaluate(
                from: from,
                to: to,
                mode: segment.mode,
                departAt: start,
                targetArrival: targetArrival,
                rainAversion: rainAversion
            ) {
                let targetWx = summary.wxRepresentative ?? WxFeature(timeISO: iso8601UTC(start), rain: 0, wind: 0, feels: 0, visibility: 0, thunder: false)
                let advice = Advice(
                    impact: summary.impact,
                    tags: summary.tags,
                    message: summary.message,
                    score: summary.score,
                    weatherScore: summary.weatherScore,
                    timeScore: summary.timeScore,
                    scenarioScores: summary.scenarioScores,
                    riskDetails: summary.riskDetails
                )
                let wear = rules.wear(today: targetWx, yday: ydayWx, mode: segment.mode)
                return SegmentResult(segment: segment, advice: advice, wear: wear, wxUsed: targetWx)
            }
        }

        // 出発±15分の範囲でOpen-Meteoから1時間単位を取得して、最も近い時刻を採用
        let latLng = segment.latLngFrom ?? LatLng(latitude: 35.0, longitude: 135.0) // 仮
        let isoStart = iso8601UTC(Calendar.current.date(byAdding: .minute, value: -30, to: start)!)
        let isoEnd = iso8601UTC(end)
        let hours = try await weather.hourly(lat: latLng.latitude, lon: latLng.longitude, startISO: isoStart, endISO: isoEnd)
        let target = nearest(to: start, in: hours)

        // 移動時間中の全時間帯の天気データを取得（確率計算用）
        let travelHours = filterWeatherDuringTravel(hours: hours, start: start, durationMin: segment.durationMin)

        let ctx = SegmentContext(mode: segment.mode, rainAversion: rainAversion, start: start, durationMin: segment.durationMin, sampleLatLon: latLng)
        let advice = rules.evaluate(mode: ctx.mode, wx: target, rainAversion: ctx.rainAversion, travelHours: travelHours)
        // 危険系優先 → wearはセカンドライン
        let wear = rules.wear(today: target, yday: ydayWx, mode: ctx.mode)

        return SegmentResult(segment: segment, advice: advice, wear: wear, wxUsed: target)
    }
    
    // 移動時間中の天気データを抽出
    private func filterWeatherDuringTravel(hours: [WxFeature], start: Date, durationMin: Int) -> [WxFeature] {
        let end = Calendar.current.date(byAdding: .minute, value: durationMin, to: start)!
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        df.timeZone = .gmt
        
        return hours.filter { weather in
            guard let weatherDate = df.date(from: weather.timeISO) else { return false }
            return weatherDate >= start && weatherDate <= end
        }
    }

    // Helpers
    private func iso8601UTC(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
    
    private func nearest(to date: Date, in list: [WxFeature]) -> WxFeature {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        df.timeZone = .gmt
        return list.min(by: {
            abs((df.date(from: $0.timeISO) ?? date).timeIntervalSince(date)) <
            abs((df.date(from: $1.timeISO) ?? date).timeIntervalSince(date))
        })!
    }
    
    private func dateForToday(timeString: String) -> Date {
        var comps = DateComponents()
        let parts = timeString.split(separator: ":").map { Int($0)! }
        let cal = Calendar.current
        let now = Date()
        comps.year = cal.component(.year, from: now)
        comps.month = cal.component(.month, from: now)
        comps.day = cal.component(.day, from: now)
        comps.hour = parts[0]
        comps.minute = parts[1]
        return cal.date(from: comps)!
    }

    private func dateForTodayOrNext(timeString: String, reference: Date) -> Date {
        let base = dateForToday(timeString: timeString)
        if base >= reference {
            return base
        }
        return Calendar.current.date(byAdding: .day, value: 1, to: base) ?? base
    }
}
