//
//  Notifier.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import UserNotifications

enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }
    
    static func schedule(at date: Date, title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
    
    /// セグメントの出発15分前に通知をスケジュール
    static func scheduleForSegment(_ segment: Segment, advice: Advice, wear: WearAdvice?) {
        // 出発時刻を取得
        let timeParts = segment.startTime.split(separator: ":").compactMap { Int($0) }
        guard timeParts.count == 2 else { return }
        
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = timeParts[0]
        components.minute = timeParts[1]
        
        guard let departureTime = calendar.date(from: components) else { return }
        
        // 出発15分前
        guard let notificationTime = calendar.date(byAdding: .minute, value: -15, to: departureTime) else { return }
        
        // 通知が過去の場合はスキップ
        if notificationTime < now { return }
        
        // 影響度テキスト
        let impactText = ["低", "中", "高"][advice.impact.rawValue]
        
        // 本文作成
        var body = "影響 \(impactText)：\(advice.message)"
        if let w = wear {
            body += "（\(w.message)）"
        }
        
        let id = "segment_\(segment.id)"
        schedule(at: notificationTime, title: segment.name, body: body, id: id)
    }
    
    /// セグメントの通知を削除
    static func cancelForSegment(_ segment: Segment) {
        let id = "segment_\(segment.id)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
    
    /// すべての通知を削除
    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

