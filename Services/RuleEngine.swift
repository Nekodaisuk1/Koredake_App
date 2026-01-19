//
//  RuleEngine.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import Foundation

struct Rule: Decodable {
    struct When: Decodable {
        var mode: [String]?
        var thunder: Bool?
        var rain_gte: Double?
        var rain_lt: Double?
        var wind_gte: Double?
        var feels_gte: Double?
        var feels_lte: Double?
        var visibility_lt: Double?
    }
    var id: String
    var when: When
    var impact: String
    var priority: Int
}

struct WearBand: Decodable {
    let min: Int
    let max: Int
    let text: String
}

struct WearAdjust: Decodable {
    let wind_ms_gte: Double
    let rain_mmph_gte: Double
    let delta_minus: Int
}

struct RuleTable: Decodable {
    let rules: [Rule]
    let messages: [String: String]
    let suffix: [String: String]
    let wear: [WearBand]
    let wearAdjust: WearAdjust
}

struct RuleMatch {
    let id: String
    let impact: Impact
    let priority: Int
}

final class RuleEngine {
    private let table: RuleTable
    // 互換グループ: 左側が上位互換 (上位を表示)
    private let compatibilityGroups: [[String]] = [
        ["heavy_rain", "light_rain"]
    ]
    
    init() {
        let url = Bundle.main.url(forResource: "rules", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        table = try! JSONDecoder().decode(RuleTable.self, from: data)
    }
    
    func evaluate(mode: Mode, wx: WxFeature, rainAversion: Int, travelHours: [WxFeature] = []) -> Advice {
        var hits: [(tag: String, impact: Impact, prio: Int)] = []

        // 雨のしきい値補正
        let lightRain = (rainAversion >= 2) ? 0.0 : 0.1
        let heavyRain = (rainAversion >= 2) ? 0.5 : 1.0

        for r in table.rules {
            // 動的補正を適用した上で条件を評価
            var ok = true
            if let ms = r.when.mode, !ms.contains(mode.rawValue) { ok = false }
            if let t = r.when.thunder, t != wx.thunder { ok = false }
            if let g = r.when.rain_gte {
                let th = (g == 0.1 ? lightRain : (g == 1.0 ? heavyRain : g))
                if wx.rain < th { ok = false }
            }
            if let l = r.when.rain_lt, !(wx.rain < l) { ok = false }
            if let g = r.when.wind_gte, !(wx.wind >= g) { ok = false }
            if let g = r.when.feels_gte, !(wx.feels >= g) { ok = false }
            if let l = r.when.feels_lte, !(wx.feels <= l) { ok = false }
            if let l = r.when.visibility_lt, !(wx.visibility < l) { ok = false }
            if ok {
                let imp = Impact(rawValue: ["low": 0, "mid": 1, "high": 2][r.impact]!)!
                hits.append((r.id, imp, r.priority))
            }
        }

        let impact = hits.map { $0.impact }.max(by: { $0.rawValue < $1.rawValue }) ?? .low
        let sorted = hits.sorted { $0.prio > $1.prio }
        let primary = sorted.first?.tag
        let secondary = sorted.dropFirst().first?.tag

        func phrase(_ tag: String?) -> String {
            guard let t = tag, let m = table.messages[t] else { return "概ね良好" }
            return m
        }

        func suffix(_ wx: WxFeature, primary: String?) -> String? {
            guard let p = primary else { return nil }
            if p == "heavy_rain" || p == "light_rain" {
                // 雨量0.0mm/hの場合はサフィックスを表示しない
                if wx.rain < 0.01 { return nil }
                return String(format: table.suffix["rain"] ?? "", wx.rain)
            }
            if p == "strong_wind" {
                return String(format: table.suffix["wind"] ?? "", wx.wind)
            }
            if p == "heat" || p == "cold" {
                return String(format: table.suffix["feels"] ?? "", wx.feels)
            }
            return nil
        }

        // 雨 < 0.1mm/h のときは傘系文を抑制し「概ね良好」へフォールバック
        var effectivePrimary = primary
        if let p = primary, (p == "heavy_rain" || p == "light_rain"), wx.rain < 0.1 {
            effectivePrimary = nil
        }

        var msg = phrase(effectivePrimary)
        if let sec = secondary, msg.count < 18, effectivePrimary != nil {
            let half = phrase(sec).split(separator: "。").first ?? ""
            if !half.isEmpty { msg += "／" + half }
        }
        if let suf = suffix(wx, primary: effectivePrimary), msg.count + suf.count < 28 {
            msg += " " + suf
        }

        // 雨量0.0で傘系タグが唯一の場合は影響度を低に下げる
        let finalImpact = (effectivePrimary == nil && primary != nil && wx.rain < 0.01) ? Impact.low : impact

        // リスク詳細情報を計算（移動時間中の確率）
        let riskDetails = calculateRiskDetails(mode: mode, travelHours: travelHours.isEmpty ? [wx] : travelHours, rainAversion: rainAversion)

        return Advice(impact: finalImpact, tags: sorted.map { $0.tag }, message: msg, score: nil, weatherScore: nil, timeScore: nil, scenarioScores: nil, riskDetails: riskDetails)
    }

    func matchingRules(mode: Mode, wx: WxFeature, rainAversion: Int) -> [RuleMatch] {
        var matches: [RuleMatch] = []

        // 雨のしきい値補正
        let lightRain = (rainAversion >= 2) ? 0.0 : 0.1
        let heavyRain = (rainAversion >= 2) ? 0.5 : 1.0

        for r in table.rules {
            var ok = true
            if let ms = r.when.mode, !ms.contains(mode.rawValue) { ok = false }
            if let t = r.when.thunder, t != wx.thunder { ok = false }
            if let g = r.when.rain_gte {
                let th = (g == 0.1 ? lightRain : (g == 1.0 ? heavyRain : g))
                if wx.rain < th { ok = false }
            }
            if let l = r.when.rain_lt, !(wx.rain < l) { ok = false }
            if let g = r.when.wind_gte, !(wx.wind >= g) { ok = false }
            if let g = r.when.feels_gte, !(wx.feels >= g) { ok = false }
            if let l = r.when.feels_lte, !(wx.feels <= l) { ok = false }
            if let l = r.when.visibility_lt, !(wx.visibility < l) { ok = false }
            if ok {
                let imp = Impact(rawValue: ["low": 0, "mid": 1, "high": 2][r.impact] ?? 0) ?? .low
                matches.append(RuleMatch(id: r.id, impact: imp, priority: r.priority))
            }
        }

        return matches
    }

    func impactForMatches(_ matches: [RuleMatch]) -> Impact {
        matches.map { $0.impact }.max(by: { $0.rawValue < $1.rawValue }) ?? .low
    }

    func riskDetails(mode: Mode, travelHours: [WxFeature], rainAversion: Int) -> [RiskDetail] {
        calculateRiskDetails(mode: mode, travelHours: travelHours, rainAversion: rainAversion)
    }

    func message(for tag: String) -> String? {
        table.messages[tag]
    }

    func reduceCompatibleTags(tagWeights: [String: Double]) -> [String] {
        let ruleById = Dictionary(uniqueKeysWithValues: table.rules.map { ($0.id, $0) })
        var remaining = tagWeights
        var finalIds: [String] = []

        for group in compatibilityGroups {
            let present = group.filter { remaining[$0] != nil }
            if present.isEmpty { continue }
            let chosen = present.sorted { id1, id2 in
                let p1 = ruleById[id1]?.priority ?? 0
                let p2 = ruleById[id2]?.priority ?? 0
                if p1 != p2 { return p1 > p2 }
                return (remaining[id1] ?? 0) > (remaining[id2] ?? 0)
            }.first!
            finalIds.append(chosen)
            for id in present { remaining.removeValue(forKey: id) }
        }

        let sortedRemaining = remaining.keys.sorted { id1, id2 in
            let w1 = remaining[id1] ?? 0
            let w2 = remaining[id2] ?? 0
            if w1 != w2 { return w1 > w2 }
            return (ruleById[id1]?.priority ?? 0) > (ruleById[id2]?.priority ?? 0)
        }
        finalIds.append(contentsOf: sortedRemaining)
        return finalIds
    }
    
    // リスクの詳細情報（内容と確率）を計算
    private func calculateRiskDetails(mode: Mode, travelHours: [WxFeature], rainAversion: Int) -> [RiskDetail] {
        guard !travelHours.isEmpty else { return [] }
        
        // 雨のしきい値補正
        let lightRain = (rainAversion >= 2) ? 0.0 : 0.1
        let heavyRain = (rainAversion >= 2) ? 0.5 : 1.0
        
        // 優先度順にソートするために、rule.idを保持
        var riskDetailsWithRuleId: [(ruleId: String, riskDetail: RiskDetail)] = []
        
        // 各ルールについて確率を計算
        for rule in table.rules {
            // モード条件をチェック
            if let modes = rule.when.mode, !modes.contains(mode.rawValue) {
                continue
            }
            
            var matchingCount = 0
            
            for wx in travelHours {
                var matches = true
                
                if let t = rule.when.thunder, t != wx.thunder { matches = false }
                if let g = rule.when.rain_gte {
                    let th = (g == 0.1 ? lightRain : (g == 1.0 ? heavyRain : g))
                    if wx.rain < th { matches = false }
                }
                if let l = rule.when.rain_lt, !(wx.rain < l) { matches = false }
                if let g = rule.when.wind_gte, !(wx.wind >= g) { matches = false }
                if let g = rule.when.feels_gte, !(wx.feels >= g) { matches = false }
                if let l = rule.when.feels_lte, !(wx.feels <= l) { matches = false }
                if let l = rule.when.visibility_lt, !(wx.visibility < l) { matches = false }
                
                if matches {
                    matchingCount += 1
                }
            }
            
            if matchingCount > 0 {
                let probability = Int((Double(matchingCount) / Double(travelHours.count)) * 100)
                var riskName = table.messages[rule.id] ?? rule.id
                // 句点を除去
                riskName = riskName.replacingOccurrences(of: "。", with: "")
                riskDetailsWithRuleId.append((ruleId: rule.id, riskDetail: RiskDetail(ruleId: rule.id, riskName: riskName, probability: probability)))
            }
        }
        
        // detailsById: ruleId -> RiskDetail
        var detailsById: [String: RiskDetail] = [:]
        for pair in riskDetailsWithRuleId { detailsById[pair.ruleId] = pair.riskDetail }

        // ルール辞書: id -> Rule
        let ruleById = Dictionary(uniqueKeysWithValues: table.rules.map { ($0.id, $0) })

        var finalList: [RiskDetail] = []

        // 互換グループごとに上位互換のみを残す
        for group in compatibilityGroups {
            let present = group.filter { detailsById[$0] != nil }
            if present.isEmpty { continue }

            // present の中で優先度が高いものを選ぶ
            let chosenId = present.sorted { id1, id2 in
                let p1 = ruleById[id1]?.priority ?? 0
                let p2 = ruleById[id2]?.priority ?? 0
                if p1 != p2 { return p1 > p2 }
                return (detailsById[id1]?.probability ?? 0) > (detailsById[id2]?.probability ?? 0)
            }.first!

            if let chosen = detailsById[chosenId] { finalList.append(chosen) }

            // グループ内の要素を削除して重複表示を避ける
            for id in present { detailsById.removeValue(forKey: id) }
        }

        // 残った要素は優先度順に追加
        let remainingSorted = detailsById.keys.sorted { id1, id2 in
            let p1 = ruleById[id1]?.priority ?? 0
            let p2 = ruleById[id2]?.priority ?? 0
            if p1 != p2 { return p1 > p2 }
            return (detailsById[id1]?.probability ?? 0) > (detailsById[id2]?.probability ?? 0)
        }
        for id in remainingSorted { if let d = detailsById[id] { finalList.append(d) } }

        return finalList
    }

    func wear(today: WxFeature, yday: WxFeature?, mode: Mode) -> WearAdvice? {
        guard var d = yday.map({ today.feels - $0.feels }) else { return nil }
        if (mode == .walk || mode == .bike) {
            if today.wind >= table.wearAdjust.wind_ms_gte { d -= Double(table.wearAdjust.delta_minus) }
            if today.rain >= table.wearAdjust.rain_mmph_gte { d -= Double(table.wearAdjust.delta_minus) }
        }
        let di = Int(round(d))
        // 危険系は服装より上位で別途処理（呼び出し側で制御）
        let band = table.wear.first { di >= $0.min && di <= $0.max }?.text ?? "昨日比較なし"
        return WearAdvice(message: band, delta: di)
    }
}
