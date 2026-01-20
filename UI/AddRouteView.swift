//
//  AddRouteView.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import SwiftUI
import WidgetKit

struct AddRouteView: View {
    @Environment(\.dismiss) var dismiss
    let onSave: () -> Void
    let editingSegment: Segment?  // 編集モードの場合、編集対象のセグメント
    
    @State private var mode: Mode = .walk
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var fromPlace: String = ""
    @State private var toPlace: String = ""
    @State private var fromLatLng: LatLng?
    @State private var toLatLng: LatLng?
    @State private var fromPlaceObj: Place?
    @State private var toPlaceObj: Place?
    @State private var showingFromPicker = false
    @State private var showingToPicker = false
    @State private var goTime = Date()
    @State private var goArrivalEnabled = false
    @State private var goArrivalTime = Date()
    @State private var sameReturn = true
    @State private var returnTime: Date = {
        let cal = Calendar.current
        return cal.date(byAdding: .hour, value: 9, to: Date()) ?? Date()
    }()
    @State private var returnArrivalEnabled = false
    @State private var returnArrivalTime: Date = {
        let cal = Calendar.current
        return cal.date(byAdding: .hour, value: 10, to: Date()) ?? Date()
    }()
    @State private var durationMin: Int = 30
    
    private let daysOfWeek = ["月", "火", "水", "木", "金", "土", "日"]
    
    init(editingSegment: Segment? = nil, onSave: @escaping () -> Void) {
        self.editingSegment = editingSegment
        self.onSave = onSave
        
        // 編集モードの場合、初期値を設定
        if let segment = editingSegment {
            _mode = State(initialValue: segment.mode)
            _selectedDays = State(initialValue: Set(segment.dow))
            _fromPlace = State(initialValue: segment.fromPlace)
            _toPlace = State(initialValue: segment.toPlace)
            _fromLatLng = State(initialValue: segment.latLngFrom)
            _toLatLng = State(initialValue: segment.latLngTo)
            _durationMin = State(initialValue: segment.durationMin)
            
            // 時刻をDateに変換
            let timeParts = segment.startTime.split(separator: ":").compactMap { Int($0) }
            if timeParts.count == 2 {
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
                components.hour = timeParts[0]
                components.minute = timeParts[1]
                if let time = Calendar.current.date(from: components) {
                    _goTime = State(initialValue: time)
                }
            }
            
            if let target = segment.targetArrivalTime {
                let targetParts = target.split(separator: ":").compactMap { Int($0) }
                if targetParts.count == 2 {
                    var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
                    components.hour = targetParts[0]
                    components.minute = targetParts[1]
                    if let time = Calendar.current.date(from: components) {
                        _goArrivalTime = State(initialValue: time)
                        _goArrivalEnabled = State(initialValue: true)
                    }
                }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            formBody
                .navigationTitle(editingSegment == nil ? "ルート追加" : "ルート編集")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(isPresented: $showingFromPicker) {
                    PlacePicker(selectedPlace: $fromPlaceObj, placeholder: "出発地を検索")
                }
                .sheet(isPresented: $showingToPicker) {
                    PlacePicker(selectedPlace: $toPlaceObj, placeholder: "到着地を検索")
                }
                .onChange(of: fromPlaceObj) { newValue in
                    if let place = newValue {
                        fromPlace = place.name
                        fromLatLng = place.coordinate
                    }
                }
                .onChange(of: toPlaceObj) { newValue in
                    if let place = newValue {
                        toPlace = place.name
                        toLatLng = place.coordinate
                    }
                }
        }
    }

    private var formBody: some View {
        Form {
            moveSection
            weekdaySection
            outboundSection
            returnSection
            durationSection
        }
    }

    private var moveSection: some View {
        Section("移動手段") {
            Picker("移動手段", selection: $mode) {
                Text("徒歩").tag(Mode.walk)
                Text("自転車").tag(Mode.bike)
                Text("電車").tag(Mode.train)
                Text("バス").tag(Mode.bus)
            }
            .pickerStyle(.segmented)
        }
    }

    private var weekdaySection: some View {
        Section("曜日") {
            HStack {
                ForEach(1...7, id: \.self) { day in
                    Button {
                        if selectedDays.contains(day) {
                            selectedDays.remove(day)
                        } else {
                            selectedDays.insert(day)
                        }
                    } label: {
                        Text(daysOfWeek[day - 1])
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedDays.contains(day) ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(selectedDays.contains(day) ? .white : .primary)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }

    private var outboundSection: some View {
        Section("行き") {
            HStack {
                Text("出発地")
                Spacer()
                Button(fromPlace.isEmpty ? "選択" : fromPlace) {
                    showingFromPicker = true
                }
            }
            HStack {
                Text("到着地")
                Spacer()
                Button(toPlace.isEmpty ? "選択" : toPlace) {
                    showingToPicker = true
                }
            }
            DatePicker("出発時刻", selection: $goTime, displayedComponents: .hourAndMinute)
            Toggle("到着希望時刻", isOn: $goArrivalEnabled)
            if goArrivalEnabled {
                DatePicker("到着希望", selection: $goArrivalTime, displayedComponents: .hourAndMinute)
            }

            if fromLatLng != nil || toLatLng != nil {
                Section {
                    MapPreview(
                        fromPlace: fromLatLng,
                        toPlace: toLatLng,
                        mode: mode,
                        fromName: fromPlace.isEmpty ? "出発地" : fromPlace,
                        toName: toPlace.isEmpty ? "到着地" : toPlace,
                        showWeatherPoints: false
                    )
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("ルートプレビュー")
                }
            }
        }
    }

    private var returnSection: some View {
        Section("帰り") {
            Toggle("帰りは行きと同じ", isOn: $sameReturn)
            if !sameReturn {
                HStack {
                    Text("出発地")
                    Spacer()
                    Button("選択") {
                        // TODO: Places Picker（行きの到着地をデフォルト）
                    }
                }
                HStack {
                    Text("到着地")
                    Spacer()
                    Button("選択") {
                        // TODO: Places Picker（行きの出発地をデフォルト）
                    }
                }
            }
            DatePicker("帰りの時刻", selection: $returnTime, displayedComponents: .hourAndMinute)
            Toggle("到着希望時刻", isOn: $returnArrivalEnabled)
            if returnArrivalEnabled {
                DatePicker("到着希望", selection: $returnArrivalTime, displayedComponents: .hourAndMinute)
            }
        }
    }

    private var durationSection: some View {
        Section("所要時間") {
            Stepper("\(durationMin)分", value: $durationMin, in: 5...120, step: 5)
        }
    }

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    if editingSegment != nil {
                        Button(role: .destructive) {
                            deleteRoute()
                        } label: { Text("削除") }
                    }
                    Button("キャンセル") { dismiss() }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    saveRoute()
                }
                .disabled(fromPlace.isEmpty || toPlace.isEmpty || selectedDays.isEmpty)
            }
        }
    }
    
    private func saveRoute() {
        let store = SegmentStore.shared
        
        // 行きセグメント
        let goSegment = Segment(
            name: "\(fromPlace)→\(toPlace)",
            mode: mode,
            fromPlace: fromPlace,
            toPlace: toPlace,
            startTime: timeString(from: goTime),
            targetArrivalTime: goArrivalEnabled ? timeString(from: goArrivalTime) : nil,
            durationMin: durationMin,
            dow: Array(selectedDays).sorted(),
            latLngFrom: fromLatLng,
            latLngTo: toLatLng
        )
        
        // 帰りセグメント
        let returnSegment: Segment
        if sameReturn {
            // 行きと同じ（反転）
            returnSegment = Segment(
                name: "\(toPlace)→\(fromPlace)",
                mode: mode,
                fromPlace: toPlace,
                toPlace: fromPlace,
                startTime: timeString(from: returnTime),
                targetArrivalTime: returnArrivalEnabled ? timeString(from: returnArrivalTime) : nil,
                durationMin: durationMin,
                dow: Array(selectedDays).sorted(),
                latLngFrom: toLatLng,
                latLngTo: fromLatLng
            )
        } else {
            // TODO: 帰りの出発地/到着地を取得
            returnSegment = Segment(
                name: "\(toPlace)→\(fromPlace)",
                mode: mode,
                fromPlace: toPlace,
                toPlace: fromPlace,
                startTime: timeString(from: returnTime),
                targetArrivalTime: returnArrivalEnabled ? timeString(from: returnArrivalTime) : nil,
                durationMin: durationMin,
                dow: Array(selectedDays).sorted(),
                latLngFrom: toLatLng,
                latLngTo: fromLatLng
            )
        }
        
        // Perform file IO on a background queue to avoid blocking the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if let editing = editingSegment {
                    // 編集モード
                    var updatedSegment = goSegment
                    updatedSegment.id = editing.id  // IDを保持
                    try store.updateSegment(updatedSegment)
                } else {
                    // 新規追加モード
                    try store.addSegments([goSegment, returnSegment])
                }
                DispatchQueue.main.async {
                    onSave()
                    // Ask the widget to refresh immediately
                    WidgetCenter.shared.reloadAllTimelines()
                    dismiss()
                }
            } catch {
                print("保存エラー: \(error)")
                DispatchQueue.main.async {
                    // TODO: show user-facing error
                }
            }
        }
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func deleteRoute() {
        guard let editing = editingSegment else { return }
        let store = SegmentStore.shared
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try store.deleteSegment(id: editing.id)
                DispatchQueue.main.async {
                    onSave()
                    WidgetCenter.shared.reloadAllTimelines()
                    dismiss()
                }
            } catch {
                print("削除エラー: \(error)")
            }
        }
    }
}
