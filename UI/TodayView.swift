//
//  TodayView.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import SwiftUI
import CoreLocation

struct TodayView: View {
    @State private var segments: [Segment] = []
    @State private var results: [SegmentResult] = []
    @State private var loading = false
    @State private var showingAddRoute = false
    @State private var editingSegment: Segment?
    @State private var showingDeleteAlert = false
    @State private var segmentToDelete: Segment?
    @State private var detailSegment: Segment?
    @State private var currentLocation: CLLocation?
    @State private var locationName = "位置情報を取得中..."
    @State private var currentWeather: WxFeature?
    @State private var hourlyWeather: [WxFeature] = []
    @State private var dailyWeather: [(day: String, temp: Double, icon: WeatherIcon)] = []
    
    let evaluator = SegmentEvaluator(weather: OpenMeteoClient())
    let store = SegmentStore.shared
    let weatherClient = OpenMeteoClient()
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ZStack {
            // グラデーション背景
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.2, green: 0.4, blue: 0.8),
                    Color(red: 0.3, green: 0.5, blue: 0.9)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // ヘッダー
                    headerView
                    
                    // 現在の天気
                    currentWeatherView
                    
                    // 詳細情報
                    detailView
                    
                    // 今日の予定
                    if !results.isEmpty {
                        todayScheduleView
                    }
                    
                    // 時間別予報
                    hourlyForecastView
                    
                    // 日別予報
                    dailyForecastView
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .overlay(alignment: .topTrailing) {
            // ハンバーガーメニュー
                        Button {
                            showingAddRoute = true
                        } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
                }
            }
            .sheet(isPresented: $showingAddRoute) {
                AddRouteView(editingSegment: editingSegment, onSave: {
                    Task {
                        await loadSegments()
                        await refresh()
                    }
                    editingSegment = nil
                })
            }
            .alert("ルートを削除", isPresented: $showingDeleteAlert) {
                Button("キャンセル", role: .cancel) {
                    segmentToDelete = nil
                }
                Button("削除", role: .destructive) {
                    if let segment = segmentToDelete {
                        deleteSegment(segment)
                    }
                    segmentToDelete = nil
                }
            } message: {
                if let segment = segmentToDelete {
                    Text("「\(segment.name)」を削除しますか？")
                }
            }
        .task {
            locationManager.requestLocation()
            await setupLocation()
            await loadSegments()
                await refresh()
        }
        .onChange(of: locationManager.location) { _ in
            Task {
                if let location = locationManager.location {
                    currentLocation = location
                    await reverseGeocode(location: location)
                    await loadWeather()
                }
            }
        }
        .sheet(item: $detailSegment, onDismiss: {
            Task {
                await loadSegments()
                await refresh()
            }
        }) { segment in
            RouteDetailView(segment: segment)
        }
    }
    
    // MARK: - ヘッダー
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedDate)
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
            
            Text("現在の \(locationName)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - 現在の天気
    private var currentWeatherView: some View {
        VStack(spacing: 16) {
            if let weather = currentWeather {
                Text("\(Int(weather.feels))°C")
                    .font(.system(size: 72, weight: .light))
                    .foregroundColor(.white)
                
                WeatherIconView(weather: weather, size: 80)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 詳細情報
    private var detailView: some View {
        HStack(spacing: 40) {
            if let weather = currentWeather {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "cloud.rain")
                            .foregroundColor(.white.opacity(0.9))
                        Text("雨の可能性")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Text("\(Int(min(weather.rain * 10, 100)))%")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "wind")
                            .foregroundColor(.white.opacity(0.9))
                        Text("風")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Text("\(Int(weather.wind * 3.6)) km/h")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 今日の予定
    private var todayScheduleView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日の予定")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                ForEach(results, id: \.segment.id) { result in
                    ScheduleRow(
                        result: result,
                        onTap: {
                            detailSegment = result.segment
                        },
                        onEdit: {
                            editingSegment = result.segment
                            showingAddRoute = true
                        },
                        onDelete: {
                            segmentToDelete = result.segment
                            showingDeleteAlert = true
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - 時間別予報
    private var hourlyForecastView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("時間別予報")
                .font(.headline)
                .foregroundColor(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(hourlyWeather.prefix(12).enumerated()), id: \.offset) { _, weather in
                        HourlyWeatherCard(weather: weather)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - 日別予報
    private var dailyForecastView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今後の予報")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                ForEach(Array(dailyWeather.enumerated()), id: \.offset) { _, item in
                    DailyWeatherRow(day: item.day, temp: item.temp, icon: item.icon)
                }
            }
        }
    }
    
    // MARK: - ヘルパー
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "今日, dd/MM"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: Date())
    }
    
    // MARK: - データロード
    private func setupLocation() async {
        if let location = locationManager.location {
            currentLocation = location
            await reverseGeocode(location: location)
            await loadWeather()
        } else {
            // デフォルト位置（東京）
            currentLocation = CLLocation(latitude: 35.6812, longitude: 139.7671)
            locationName = "東京"
            await loadWeather()
        }
    }
    
    private func reverseGeocode(location: CLLocation) async {
        let geocoder = CLGeocoder()
        do {
            if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
               let placemark = placemarks.first {
                locationName = placemark.locality ?? placemark.administrativeArea ?? "不明な場所"
            } else {
                locationName = "位置情報"
            }
        }
    }
    
    private func loadWeather() async {
        let location = currentLocation ?? locationManager.location ?? CLLocation(latitude: 35.6812, longitude: 139.7671)
        
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startISO = formatter.string(from: now)
        let endISO = formatter.string(from: endDate)
        
        do {
            let weatherData = try await weatherClient.hourly(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                startISO: startISO,
                endISO: endISO
            )
            
            // 現在の天気（最初のデータ）
            if !weatherData.isEmpty {
                currentWeather = weatherData.first
            }
            
            // 時間別予報（今日の残り）
            let todayEnd = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
            hourlyWeather = weatherData.filter { weather in
                if let date = parseISO8601(weather.timeISO) {
                    return date < todayEnd
                }
                return false
            }
            
            // 日別予報（各日の代表的な天気）
            dailyWeather = generateDailyWeather(from: weatherData)
        } catch {
            print("天気データの取得に失敗: \(error)")
        }
    }
    
    private func generateDailyWeather(from hourly: [WxFeature]) -> [(day: String, temp: Double, icon: WeatherIcon)] {
        var daily: [String: (date: Date, weathers: [WxFeature])] = [:]
        
        for weather in hourly {
            guard let date = parseISO8601(weather.timeISO) else { continue }
            let dayKey = formatDay(date)
            
            if daily[dayKey] == nil {
                daily[dayKey] = (date: date, weathers: [])
            }
            daily[dayKey]?.weathers.append(weather)
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        
        struct DailyWeatherItem {
            let day: String
            let temp: Double
            let icon: WeatherIcon
            let date: Date
        }
        
        let items: [DailyWeatherItem] = daily.compactMap { key, data in
            guard !data.weathers.isEmpty,
                  let firstWeather = data.weathers.first else { return nil }
            
            let date = data.date
            let avgTemp = data.weathers.map { $0.feels }.reduce(0, +) / Double(data.weathers.count)
            let icon = weatherIcon(for: firstWeather)
            
            // 今日より前の日付は除外
            if date < Calendar.current.startOfDay(for: Date()) {
                return nil
            }
            
            formatter.dateFormat = "EEEE"
            let dayName = formatter.string(from: date)
            
            return DailyWeatherItem(day: dayName, temp: avgTemp, icon: icon, date: date)
        }
        
        return items.sorted { $0.date < $1.date }
            .prefix(7)
            .map { (day: $0.day, temp: $0.temp, icon: $0.icon) }
    }
    
    private func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
    
    func loadSegments() async {
        segments = store.loadSegments()
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        
        let weekday = Calendar.current.component(.weekday, from: Date())
        let dow = weekday == 1 ? 7 : weekday - 1
        
        let todaySegments = segments.filter { $0.dow.contains(dow) }
        
        var out: [SegmentResult] = []
        for s in todaySegments {
            if let res = try? await evaluator.evaluate(segment: s, rainAversion: 2, ydayWx: nil) {
                out.append(res)
                Notifier.scheduleForSegment(s, advice: res.advice, wear: res.wear)
            }
        }
        
        out.sort { $0.segment.startTime < $1.segment.startTime }
        results = out
        
        try? store.saveTodayResults(out)
    }
    
    private func deleteSegment(_ segment: Segment) {
        Task {
            do {
                try store.deleteSegment(id: segment.id)
                await loadSegments()
                await refresh()
            } catch {
                print("削除エラー: \(error)")
            }
        }
    }
}


// MARK: - Hourly Weather Card

struct HourlyWeatherCard: View {
    let weather: WxFeature
    
    var body: some View {
        VStack(spacing: 8) {
            Text(timeString)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            
            WeatherIconView(weather: weather, size: 32)
            
            Text("\(Int(weather.feels))°C")
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .frame(width: 60)
    }
    
    private var timeString: String {
        guard let date = parseISO8601(weather.timeISO) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
}

// MARK: - Schedule Row

struct ScheduleRow: View {
    let result: SegmentResult
    var onTap: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1行目：時刻+区間名
            HStack {
                Text("\(result.segment.startTime) \(result.segment.name)")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                ImpactChip(impact: result.advice.impact)
            }
            
            // リスク詳細情報（内容と確率）
            if let riskDetails = result.advice.riskDetails, !riskDetails.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(riskDetails, id: \.riskName) { risk in
                        HStack {
                            Text(risk.riskName)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            Text("\(risk.probability)%")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(probabilityColor(risk.probability))
                        }
                    }
                }
                if let timeScore = result.advice.timeScore, timeScore >= 70 {
                    Text("到着マージン小。早め出発を")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
            } else {
                Text(result.advice.message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            
            // 服装アドバイス
            if let wear = result.wear {
                HStack {
                    Spacer()
                    Text(wear.message)
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.15))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            Button {
                onEdit?()
            } label: {
                Label("編集", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }
    
    private func probabilityColor(_ probability: Int) -> Color {
        if probability >= 70 {
            return .red
        } else if probability >= 40 {
            return .orange
        } else {
            return .yellow
        }
    }
}

// MARK: - Daily Weather Row

struct DailyWeatherRow: View {
    let day: String
    let temp: Double
    let icon: WeatherIcon
    
    var body: some View {
        HStack {
            Text(day)
                .font(.subheadline)
                .foregroundColor(.white)
            
            Spacer()
            
            Image(systemName: icon.systemName)
                .foregroundColor(.white.opacity(0.9))
            
            Text("\(Int(temp))°C")
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Location Manager

@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    
    override init() {
        super.init()
        manager.delegate = self
    }
    
    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            location = locations.first
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("位置情報の取得に失敗: \(error.localizedDescription)")
            // デフォルト位置を使用
            location = CLLocation(latitude: 35.6812, longitude: 139.7671)
        }
    }
}
