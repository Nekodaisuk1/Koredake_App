//
//  SegmentStore.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import Foundation

struct TodayResult: Codable {
    var segments: [SegmentResult]
    var updatedAt: String
}

final class SegmentStore {
    static let shared = SegmentStore()
    
    // App Groups識別子
    private let appGroupID = "group.ekaderok.Koredake.shared"
    
    private let documentsURL: URL
    private let segmentsFile: URL
    private let todayFile: URL
    
    private init() {
        let fileManager = FileManager.default
        
        // App Groupsが設定されている場合はそちらを使用
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            documentsURL = containerURL
        } else {
            documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        
        segmentsFile = documentsURL.appendingPathComponent("segments.json")
        todayFile = documentsURL.appendingPathComponent("today.json")
    }
    
    /// ウィジェット用：App Groups経由でtoday.jsonを読み込む
    /// ウィジェット拡張から直接App Groupコンテナにアクセス
    static func loadTodayResultsForWidget() -> [SegmentResult]? {
        let appGroupID = "group.ekaderok.Koredake.shared"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        
        let todayFile = containerURL.appendingPathComponent("today.json")
        guard let data = try? Data(contentsOf: todayFile),
              let today = try? JSONDecoder().decode(TodayResult.self, from: data) else {
            return nil
        }
        return today.segments
    }
    
    // MARK: - Segments
    
    func loadSegments() -> [Segment] {
        guard let data = try? Data(contentsOf: segmentsFile),
              let segments = try? JSONDecoder().decode([Segment].self, from: data) else {
            return []
        }
        let filtered = removeDemoSegments(from: segments)
        if filtered.count != segments.count {
            try? saveSegments(filtered)
        }
        return filtered
    }
    
    func saveSegments(_ segments: [Segment]) throws {
        let data = try JSONEncoder().encode(segments)
        try data.write(to: segmentsFile)
    }
    
    func addSegment(_ segment: Segment) throws {
        var segments = loadSegments()
        segments.append(segment)
        try saveSegments(segments)
    }
    
    func addSegments(_ newSegments: [Segment]) throws {
        var segments = loadSegments()
        segments.append(contentsOf: newSegments)
        try saveSegments(segments)
    }
    
    func deleteSegment(id: String) throws {
        var segments = loadSegments()
        segments.removeAll { $0.id == id }
        try saveSegments(segments)
    }

    /// Update an existing segment by id. Throws if write fails.
    func updateSegment(_ segment: Segment) throws {
        var segments = loadSegments()
        if let idx = segments.firstIndex(where: { $0.id == segment.id }) {
            segments[idx] = segment
        } else {
            // If not found, append as fallback
            segments.append(segment)
        }
        try saveSegments(segments)
    }
    
    
    // MARK: - Today Results
    
    func saveTodayResults(_ results: [SegmentResult]) throws {
        let today = TodayResult(
            segments: results,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let data = try JSONEncoder().encode(today)
        try data.write(to: todayFile)
    }
    
    func loadTodayResults() -> [SegmentResult]? {
        guard let data = try? Data(contentsOf: todayFile),
              let today = try? JSONDecoder().decode(TodayResult.self, from: data) else {
            return nil
        }
        return today.segments
    }

    private func removeDemoSegments(from segments: [Segment]) -> [Segment] {
        let demoNames: Set<String> = ["自宅→○○駅", "○○駅→学校"]
        return segments.filter { segment in
            if demoNames.contains(segment.name) { return false }
            if segment.fromPlace.contains("○○") || segment.toPlace.contains("○○") { return false }
            return true
        }
    }
}
