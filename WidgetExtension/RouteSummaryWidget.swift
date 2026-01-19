//
//  RouteSummaryWidget.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import WidgetKit
import SwiftUI

struct RouteEntry: TimelineEntry {
    let date: Date
    let title: String
    let impact: Impact
    let score: Int?
    let weatherScore: Int?
    let timeScore: Int?
    let message: String
    let risks: [String]  // リスクのリスト（例: ["雷注意", "傘必須"]）
    let wearAdvice: String?  // 服装アドバイス（例: "昨日より厚着で"）
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> RouteEntry {
        RouteEntry(date: Date(), title: "今日のリスク", impact: .mid, score: 60, weatherScore: 55, timeScore: 30, message: "", risks: ["折りたたみ傘あると安心"], wearAdvice: "昨日より厚着で")
    }
    
    func getSnapshot(in context: Context, completion: @escaping (RouteEntry) -> ()) {
        // スナップショットでは実データを読み込む
        if let entry = loadNextSegment() {
            completion(entry)
        } else {
            completion(placeholder(in: context))
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<RouteEntry>) -> ()) {
        let now = Date()
        
        // today.jsonから実データを読み込む
        guard let (entry, nextUpdate) = loadTodayRisks() else {
            // データがない場合はダミーを返す
            let dummy = RouteEntry(date: now, title: "データなし", impact: .low, score: nil, weatherScore: nil, timeScore: nil, message: "ルートを追加してください", risks: [], wearAdvice: nil)
            completion(Timeline(entries: [dummy], policy: .after(Calendar.current.date(byAdding: .hour, value: 1, to: now)!)))
            return
        }
        
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
    
    /// 今日の全予定からリスクを集約
    private func loadTodayRisks() -> (RouteEntry, Date)? {
        guard let results = SegmentStore.loadTodayResultsForWidget(),
              !results.isEmpty else {
            return nil
        }
        
        let now = Date()
        let calendar = Calendar.current
        
    // 全セグメントからリスクを集約（ruleId をキーに最大確率を保持）
    var allRisksById: [String: (name: String, probability: Int)] = [:]
        var maxImpact = Impact.low
        var wearAdvices: [String] = []
        var maxScore: Int?
        var maxWeatherScore: Int?
        var maxTimeScore: Int?
        
        for result in results {
            // 影響度の最大値を更新
            if result.advice.impact.rawValue > maxImpact.rawValue {
                maxImpact = result.advice.impact
            }
            if let score = result.advice.score {
                if maxScore == nil || score > (maxScore ?? 0) {
                    maxScore = score
                }
            }
            if let score = result.advice.weatherScore {
                if maxWeatherScore == nil || score > (maxWeatherScore ?? 0) {
                    maxWeatherScore = score
                }
            }
            if let score = result.advice.timeScore {
                if maxTimeScore == nil || score > (maxTimeScore ?? 0) {
                    maxTimeScore = score
                }
            }
            
            // リスク詳細を集約（ruleId をキー）
            if let riskDetails = result.advice.riskDetails {
                for risk in riskDetails {
                    let existing = allRisksById[risk.ruleId]
                    if existing == nil || risk.probability > existing!.probability {
                        allRisksById[risk.ruleId] = (name: risk.riskName, probability: risk.probability)
                    }
                }
            }
            
            // 服装アドバイスを収集（重複を避ける）
            if let wear = result.wear {
                let wearMessage = wear.message
                if !wearAdvices.contains(wearMessage) {
                    wearAdvices.append(wearMessage)
                }
            }
        }
        
        // 互換グループ: 左側が上位互換
        let compatibilityGroups: [[String]] = [["heavy_rain", "light_rain"]]

        // グループごとに上位互換だけ残す
        var remaining = allRisksById
        var finalIds: [String] = []

        for group in compatibilityGroups {
            let present = group.filter { remaining[$0] != nil }
            if present.isEmpty { continue }
            // present の中で確率が最大のものを選択（確率降順、同率は group の順）
            let chosen = present.sorted { id1, id2 in
                let p1 = remaining[id1]?.probability ?? 0
                let p2 = remaining[id2]?.probability ?? 0
                if p1 != p2 { return p1 > p2 }
                let i1 = group.firstIndex(of: id1) ?? Int.max
                let i2 = group.firstIndex(of: id2) ?? Int.max
                return i1 < i2
            }.first
            if let chosen = chosen { finalIds.append(chosen); remaining.removeValue(forKey: chosen) }
            for id in present { remaining.removeValue(forKey: id) }
        }

        // 残りは確率順で追加
        let remainingSortedIds = remaining.keys.sorted { id1, id2 in
            let p1 = remaining[id1]?.probability ?? 0
            let p2 = remaining[id2]?.probability ?? 0
            return p1 > p2
        }
        finalIds.append(contentsOf: remainingSortedIds)

        // 表示用の名前リストを作成
        let sortedNames = finalIds.compactMap { allRisksById[$0]?.name ?? /* if removed by group, try to get name from remaining */ nil }

        // 表示条件（40%以上、または上位3つ）
        let risksToShow: [String]
        if sortedNames.isEmpty {
            risksToShow = []
        } else {
            // use probabilities from the chosen ids
            let probs = finalIds.compactMap { id in (allRisksById[id]?.probability) ?? nil }
            let highFiltered = finalIds.enumerated().filter { index, id in
                let prob = probs[index]
                return prob >= 40 || index < 3
            }.map { idx, id in allRisksById[id]?.name ?? "" }
            if highFiltered.isEmpty {
                risksToShow = Array(sortedNames.prefix(3))
            } else {
                risksToShow = highFiltered
            }
        }
        
        // 服装アドバイス（最初の1つを採用）
        let wearAdvice = wearAdvices.first
        
        let entry = RouteEntry(
            date: now,
            title: "Koredake",
            impact: maxImpact,
            score: maxScore,
            weatherScore: maxWeatherScore,
            timeScore: maxTimeScore,
            message: "",
            risks: risksToShow,
            wearAdvice: wearAdvice
        )
        
    // 次の更新タイミング：定期更新（15分）または次のセグメントの出発時刻のいずれか早い方
    let periodicUpdate = calendar.date(byAdding: .minute, value: 15, to: now) ?? now
    let nextUpdate: Date
    var nextSegmentTime: Date?
        
        for result in results {
            let timeParts = result.segment.startTime.split(separator: ":").compactMap { Int($0) }
            guard timeParts.count == 2 else { continue }
            
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = timeParts[0]
            components.minute = timeParts[1]
            
            guard let departureTime = calendar.date(from: components) else { continue }
            let targetTime = departureTime < now ? calendar.date(byAdding: .day, value: 1, to: departureTime) ?? departureTime : departureTime
            
            if targetTime > now {
                if nextSegmentTime == nil || targetTime < nextSegmentTime! {
                    nextSegmentTime = targetTime
                }
            }
        }
        
        if let segmentTime = nextSegmentTime {
            // セグメント開始時刻が15分以内であればそれを優先、それ以外は15分後を次の更新にする
            nextUpdate = (segmentTime < periodicUpdate) ? segmentTime : periodicUpdate
        } else {
            nextUpdate = periodicUpdate
        }
        
        return (entry, nextUpdate)
    }
    
    /// today.jsonから次の区間を読み込む（簡易版、getSnapshot用）
    private func loadNextSegment() -> RouteEntry? {
        return loadTodayRisks()?.0
    }
}

struct RouteSummaryWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        let gradient = LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.2, green: 0.4, blue: 0.8),
                Color(red: 0.3, green: 0.5, blue: 0.9)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        let content = VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            Text(entry.title)
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            if let score = entry.score {
                Text("リスク \(score)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            if let weatherScore = entry.weatherScore, let timeScore = entry.timeScore {
                Text("天気 \(weatherScore) / 時間 \(timeScore)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
            }
            
            // リスクリスト
            if !entry.risks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.risks, id: \.self) { risk in
                        Text(risk)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
            } else if !entry.message.isEmpty {
                Text(entry.message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
            } else {
                Text("リスクなし")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // 服装アドバイス
            if let wear = entry.wearAdvice {
                Text(wear)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { gradient }
        } else {
            content
                .background(gradient)
                .ignoresSafeArea()
        }
    }
}

struct RouteSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RouteSummaryWidget", provider: Provider()) { entry in
            RouteSummaryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日のリスク")
        .description("今日の予定の中でリスクの高いものを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
