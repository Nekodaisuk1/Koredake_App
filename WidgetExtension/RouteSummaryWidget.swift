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
    let message: String
    let wearAdvice: String?  // 服装アドバイス（例: "昨日より厚着で"）
    let maxTemp: Int?
    let minTemp: Int?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> RouteEntry {
        RouteEntry(date: Date(), title: "今日のリスク", impact: .mid, message: "影響 中：折りたたみ傘あると安心", wearAdvice: "昨日より厚着で", maxTemp: 27, minTemp: 18)
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
            let dummy = RouteEntry(date: now, title: "データなし", impact: .low, message: "ルートを追加してください", wearAdvice: nil, maxTemp: nil, minTemp: nil)
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
        guard let next = nextResult(from: results, now: now) else {
            return nil
        }

        let impact = next.advice.impact
        let impactText = ["低", "中", "高"][impact.rawValue]
        let message = "影響 \(impactText)：\(next.advice.message)"
        let wearAdvice = next.wear?.message
        
        let temps = aggregateTemps(from: results)
        let entry = RouteEntry(
            date: now,
            title: "Koredake",
            impact: impact,
            message: message,
            wearAdvice: wearAdvice,
            maxTemp: temps.max,
            minTemp: temps.min
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

    private func nextResult(from results: [SegmentResult], now: Date) -> SegmentResult? {
        let calendar = Calendar.current
        var candidate: (result: SegmentResult, time: Date)?

        for result in results {
            let parts = result.segment.startTime.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = parts[0]
            comps.minute = parts[1]
            guard let time = calendar.date(from: comps) else { continue }
            let adjusted = time < now ? calendar.date(byAdding: .day, value: 1, to: time) ?? time : time
            if candidate == nil || adjusted < candidate!.time {
                candidate = (result, adjusted)
            }
        }

        return candidate?.result
    }

    private func aggregateTemps(from results: [SegmentResult]) -> (max: Int?, min: Int?) {
        let temps = results.map { Int($0.wxUsed.feels.rounded()) }
        return (temps.max(), temps.min())
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
                Text(entry.message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)

                if let maxTemp = entry.maxTemp, let minTemp = entry.minTemp {
                    Text("最高 \(maxTemp)℃ / 最低 \(minTemp)℃")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
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
