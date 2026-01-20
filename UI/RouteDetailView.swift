//
//  RouteDetailView.swift
//  Koredake
//
//  Created by Codex on 2025/11/08.
//

import SwiftUI
import MapKit

struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let segment: Segment

    @State private var detail: RouteRiskDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingEdit = false

    private let evaluator = RouteRiskEvaluator(weather: OpenMeteoClient())
    private let rules = RuleEngine()
    private let tempDeltaThreshold = 3.0

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                } else if let detail {
                    VStack(spacing: 12) {
                        routeMap(detail: detail)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        routeSummary(detail: detail)
                        riskLists(detail: detail)
                    }
                    .padding()
                } else {
                    Text(errorMessage ?? "詳細情報を取得できませんでした。")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .navigationTitle(segment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("編集") { showingEdit = true }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task { await loadDetail() }
        .sheet(isPresented: $showingEdit) {
            AddRouteView(editingSegment: segment, onSave: {
                dismiss()
            })
        }
    }

    private func routeMap(detail: RouteRiskDetail) -> some View {
        let weatherAlerts = weatherChangePoints(in: detail.samples)
        let tempAlerts = temperatureChangePoints(in: detail.samples, threshold: tempDeltaThreshold)
        let items = buildAnnotations(weatherAlerts: weatherAlerts, tempAlerts: tempAlerts)
        return RouteDetailMapView(route: detail.route, annotations: items)
    }

    private func routeSummary(detail: RouteRiskDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("想定ルート")
                .font(.headline)
            Text("距離 \(Int(detail.route.distance))m / 所要 \(Int(detail.route.expectedTravelTime / 60))分")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(detail.summary.message)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func riskLists(detail: RouteRiskDetail) -> some View {
        let tempAlerts = temperatureChangePoints(in: detail.samples, threshold: tempDeltaThreshold)
        let weatherAlerts = weatherChangePoints(in: detail.samples)

        return VStack(alignment: .leading, spacing: 8) {
            if !weatherAlerts.isEmpty {
                Text("天候変化ポイント")
                    .font(.headline)
                ForEach(weatherAlerts.prefix(6)) { sample in
                    Text("\(timeString(sample.time)) \(weatherChangeLabel(for: sample))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !tempAlerts.isEmpty {
                Text("気温変化ポイント")
                    .font(.headline)
                ForEach(tempAlerts.prefix(6)) { sample in
                    let temp = Int(sample.wx?.feels ?? 0)
                    Text("\(timeString(sample.time)) 体感 \(temp)℃")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weatherChangePoints(in samples: [RouteRiskSample]) -> [RouteRiskSample] {
        var results: [RouteRiskSample] = []
        let sorted = samples.sorted { $0.time < $1.time }
        var previousKey: String?
        for sample in sorted {
            guard let wx = sample.wx else { continue }
            let matches = rules.matchingRules(mode: sample.mode, wx: wx, rainAversion: 2)
            let key = matches.map { $0.id }.sorted().joined(separator: ",")
            if let prev = previousKey, key != prev {
                results.append(sample)
            }
            previousKey = key
        }
        return results
    }

    private func temperatureChangePoints(in samples: [RouteRiskSample], threshold: Double) -> [RouteRiskSample] {
        var results: [RouteRiskSample] = []
        var previousTemp: Double?
        for sample in samples {
            guard let temp = sample.wx?.feels else { continue }
            if let prev = previousTemp, abs(temp - prev) >= threshold {
                results.append(sample)
            }
            previousTemp = temp
        }
        return results
    }

    private func impactLabel(_ impact: Impact) -> String {
        ["低", "中", "高"][impact.rawValue]
    }

    private func weatherChangeLabel(for sample: RouteRiskSample) -> String {
        guard let wx = sample.wx else { return "天候変化" }
        let matches = rules.matchingRules(mode: sample.mode, wx: wx, rainAversion: 2)
        let top = matches.sorted { $0.priority > $1.priority }.first?.id
        if let tag = top, let msg = rules.message(for: tag) {
            return msg.split(separator: "。").first.map(String.init) ?? msg
        }
        return "天候変化"
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        guard let from = segment.latLngFrom, let to = segment.latLngTo else {
            errorMessage = "出発地/到着地の位置情報がありません。"
            return
        }

        let departAt = dateForToday(timeString: segment.startTime)
        let targetArrival = segment.targetArrivalTime.map { dateForTodayOrNext(timeString: $0, reference: departAt) }

        do {
            detail = try await evaluator.detail(
                from: from,
                to: to,
                mode: segment.mode,
                departAt: departAt,
                targetArrival: targetArrival,
                rainAversion: 2
            )
            if detail == nil {
                errorMessage = "ルートが取得できませんでした。"
            }
        } catch {
            errorMessage = "詳細取得に失敗: \(error.localizedDescription)"
        }
    }

    private func dateForToday(timeString: String) -> Date {
        var comps = DateComponents()
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        let cal = Calendar.current
        let now = Date()
        comps.year = cal.component(.year, from: now)
        comps.month = cal.component(.month, from: now)
        comps.day = cal.component(.day, from: now)
        comps.hour = parts.count > 0 ? parts[0] : 0
        comps.minute = parts.count > 1 ? parts[1] : 0
        return cal.date(from: comps) ?? now
    }

    private func dateForTodayOrNext(timeString: String, reference: Date) -> Date {
        let base = dateForToday(timeString: timeString)
        if base >= reference {
            return base
        }
        return Calendar.current.date(byAdding: .day, value: 1, to: base) ?? base
    }
}

private struct RouteDetailMapView: UIViewRepresentable {
    let route: MKRoute
    let annotations: [RouteDetailAnnotation]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.addOverlay(route.polyline)
        mapView.addAnnotations(annotations.map { $0.asAnnotation })
        mapView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        mapView.addOverlay(route.polyline)
        mapView.addAnnotations(annotations.map { $0.asAnnotation })
        mapView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.85)
                renderer.lineWidth = 5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let anno = annotation as? RouteDetailMKAnnotation else { return nil }
            let id = "RouteDetailAnnotation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: anno, reuseIdentifier: id)
            view.annotation = anno
            view.canShowCallout = true
            switch anno.kind {
            case .weather:
                view.markerTintColor = .systemOrange
            case .temperature:
                view.markerTintColor = .systemTeal
            }
            return view
        }
    }
}

private enum RouteDetailAnnotationKind {
    case weather
    case temperature
}

private struct RouteDetailAnnotation: Identifiable {
    let id = UUID()
    let title: String
    let coordinate: CLLocationCoordinate2D
    let kind: RouteDetailAnnotationKind

    var asAnnotation: RouteDetailMKAnnotation {
        RouteDetailMKAnnotation(title: title, coordinate: coordinate, kind: kind)
    }
}

private final class RouteDetailMKAnnotation: NSObject, MKAnnotation {
    let title: String?
    let coordinate: CLLocationCoordinate2D
    let kind: RouteDetailAnnotationKind

    init(title: String, coordinate: CLLocationCoordinate2D, kind: RouteDetailAnnotationKind) {
        self.title = title
        self.coordinate = coordinate
        self.kind = kind
    }
}

private extension RouteDetailView {
    func buildAnnotations(weatherAlerts: [RouteRiskSample], tempAlerts: [RouteRiskSample]) -> [RouteDetailAnnotation] {
        var output: [RouteDetailAnnotation] = []
        for sample in weatherAlerts {
            output.append(RouteDetailAnnotation(title: "変化", coordinate: sample.coordinate, kind: .weather))
        }
        for sample in tempAlerts {
            let temp = Int(sample.wx?.feels ?? 0)
            output.append(RouteDetailAnnotation(title: "\(temp)℃", coordinate: sample.coordinate, kind: .temperature))
        }
        return output
    }
}
