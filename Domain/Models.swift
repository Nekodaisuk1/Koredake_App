//
//  Models.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import Foundation

enum Mode: String, Codable {
    case walk, bike, train, bus
}

enum Impact: Int, Codable {
    case low = 0, mid = 1, high = 2
}

struct LatLng: Codable, Equatable {
    var latitude: Double
    var longitude: Double
}

struct Segment: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String               // "自宅→○○駅"
    var mode: Mode                 // walk/bike/train/bus
    var fromPlace: String
    var toPlace: String
    var startTime: String          // "07:20"
    var targetArrivalTime: String? // "08:00" (任意)
    var durationMin: Int           // 15
    var dow: [Int]                 // 1..7（月=1）
    var latLngFrom: LatLng?
    var latLngTo: LatLng?
}

struct WxFeature: Codable {
    var timeISO: String
    var rain: Double       // mm/h
    var wind: Double       // m/s
    var feels: Double      // ℃
    var visibility: Double // km
    var thunder: Bool
}

struct RiskDetail: Codable {
    var ruleId: String      // ルールID (例: "heavy_rain")
    var riskName: String    // "大雨", "強風"など
    var probability: Int    // 0-100の確率（%）
}

struct Advice: Codable {
    var impact: Impact
    var tags: [String]      // ["heavy_rain", "strong_wind"]
    var message: String     // 「傘必須・撥水上着で ☔1.6mm/h」
    var score: Int?         // 0-100
    var weatherScore: Int?  // 0-100
    var timeScore: Int?     // 0-100
    var scenarioScores: [String: Int]? // ["S0": 70, "S1": 65, "S2": 85]
    var riskDetails: [RiskDetail]?  // リスクの詳細情報（内容と確率）
}

struct WearAdvice: Codable {
    var message: String     // 「昨日より+3℃。1枚軽めで」
    var delta: Int
}

struct SegmentResult: Codable {
    let segment: Segment
    let advice: Advice
    let wear: WearAdvice?
    let wxUsed: WxFeature
}

// MARK: - Weather Icon

enum WeatherIcon: Codable {
    case sunBehindCloud
    case cloudRain
    case cloudBolt
    case moon
    case cloud
}

extension WeatherIcon {
    var systemName: String {
        switch self {
        case .sunBehindCloud: return "cloud.sun.fill"
        case .cloudRain: return "cloud.rain.fill"
        case .cloudBolt: return "cloud.bolt.fill"
        case .moon: return "moon.fill"
        case .cloud: return "cloud.fill"
        }
    }
}

func weatherIcon(for weather: WxFeature) -> WeatherIcon {
    // ISO8601文字列から時刻を取得
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: weather.timeISO) ?? {
        let formatter2 = ISO8601DateFormatter()
        formatter2.formatOptions = [.withInternetDateTime]
        return formatter2.date(from: weather.timeISO)
    }() else {
        // 日付が取得できない場合は現在時刻を使用
        let hour = Calendar.current.component(.hour, from: Date())
        return (hour >= 18 || hour < 6) ? .moon : .sunBehindCloud
    }
    
    let hour = Calendar.current.component(.hour, from: date)
    
    if weather.thunder {
        return .cloudBolt
    } else if weather.rain > 0.5 {
        return .cloudRain
    } else if weather.rain > 0.1 {
        return .sunBehindCloud
    } else {
        if hour >= 18 || hour < 6 {
            return .moon
        } else {
            return .sunBehindCloud
        }
    }
}
