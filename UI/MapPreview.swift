//
//  MapPreview.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import SwiftUI
import MapKit

#if canImport(GoogleMaps)
import GoogleMaps
import UIKit
#endif

@MainActor
struct MapPreview: View {
    let fromPlace: LatLng?
    let toPlace: LatLng?
    let mode: Mode
    let fromName: String
    let toName: String
    @State private var detail: RouteRiskDetail?
    @State private var errorMessage: String?
    private let evaluator = RouteRiskEvaluator(weather: OpenMeteoClient())
    private let rules = RuleEngine()
    
    var body: some View {
        // Apple Maps (MapKit) を常に使用
        mapKitPreview
            .task(id: taskKey) {
                await loadDetail()
            }
    }
    
    private var mapKitPreview: some View {
        RoutePreviewMapView(
            fromPlace: fromPlace,
            toPlace: toPlace,
            fromName: fromName,
            toName: toName,
            route: detail?.route,
            annotations: buildAnnotations()
        )
        .frame(height: 200)
        .cornerRadius(8)
    }

    private var taskKey: String {
        "\(fromPlace?.latitude ?? 0)-\(fromPlace?.longitude ?? 0)-\(toPlace?.latitude ?? 0)-\(toPlace?.longitude ?? 0)-\(mode.rawValue)"
    }

    private func loadDetail() async {
        errorMessage = nil
        guard let from = fromPlace, let to = toPlace else {
            detail = nil
            return
        }

        do {
            detail = try await evaluator.detail(
                from: from,
                to: to,
                mode: mode,
                departAt: Date(),
                targetArrival: nil,
                rainAversion: 2
            )
        } catch {
            errorMessage = error.localizedDescription
            detail = nil
        }
    }

    private func buildAnnotations() -> [RoutePreviewAnnotation] {
        var items: [RoutePreviewAnnotation] = []
        if let from = fromPlace {
            items.append(RoutePreviewAnnotation(title: fromName, coordinate: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude), kind: .start))
        }
        if let to = toPlace {
            items.append(RoutePreviewAnnotation(title: toName, coordinate: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude), kind: .end))
        }

        guard let detail else { return items }
        let changePoints = extractWeatherChangePoints(from: detail.samples)
        items.append(contentsOf: changePoints)
        return items
    }

    private func extractWeatherChangePoints(from samples: [RouteRiskSample]) -> [RoutePreviewAnnotation] {
        var seen: Set<String> = []
        var out: [RoutePreviewAnnotation] = []
        let sorted = samples.sorted { $0.time < $1.time }
        var previousKey: String?
        var previousFeels: Double?

        for sample in sorted {
            guard let wx = sample.wx else { continue }
            let matches = rules.matchingRules(mode: mode, wx: wx, rainAversion: 2)
            let tagKey = matches.map { $0.id }.sorted().joined(separator: ",")
            var changed = false
            var titleParts: [String] = []

            if let prevKey = previousKey, tagKey != prevKey {
                let top = matches.sorted { $0.priority > $1.priority }.first?.id
                if let t = top, let msg = rules.message(for: t) {
                    let head = msg.split(separator: "。").first.map(String.init) ?? msg
                    titleParts.append(head)
                } else if !tagKey.isEmpty {
                    titleParts.append("天候変化")
                }
                changed = true
            }

            if let prevFeels = previousFeels, abs(wx.feels - prevFeels) >= 3.0 {
                titleParts.append("体感\(Int(wx.feels))℃")
                changed = true
            }

            previousKey = tagKey
            previousFeels = wx.feels

            guard changed else { continue }
            let lat = (sample.coordinate.latitude * 1000).rounded() / 1000
            let lon = (sample.coordinate.longitude * 1000).rounded() / 1000
            let key = "\(lat)-\(lon)"
            if seen.contains(key) { continue }
            seen.insert(key)
            let title = titleParts.isEmpty ? "天候変化" : titleParts.joined(separator: "／")
            out.append(RoutePreviewAnnotation(title: title, coordinate: sample.coordinate, kind: .change))
        }
        return out
    }
}

private struct RoutePreviewMapView: UIViewRepresentable {
    let fromPlace: LatLng?
    let toPlace: LatLng?
    let fromName: String
    let toName: String
    let route: MKRoute?
    let annotations: [RoutePreviewAnnotation]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        updateMap(mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        updateMap(mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func updateMap(_ mapView: MKMapView) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        for item in annotations {
            mapView.addAnnotation(item.asAnnotation)
        }

        if let route {
            mapView.addOverlay(route.polyline)
            mapView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
        } else if let previewLine = makePreviewPolyline() {
            mapView.addOverlay(previewLine)
            mapView.setVisibleMapRect(previewLine.boundingMapRect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
        } else {
            updateRegionFallback(mapView)
        }
    }

    private func updateRegionFallback(_ mapView: MKMapView) {
        guard let from = fromPlace, let to = toPlace else {
            if let target = (fromPlace ?? toPlace) {
                let coordinate = CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)
                let region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                mapView.setRegion(region, animated: false)
            }
            return
        }

        let minLat = min(from.latitude, to.latitude)
        let maxLat = max(from.latitude, to.latitude)
        let minLon = min(from.longitude, to.longitude)
        let maxLon = max(from.longitude, to.longitude)
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let latDelta = max(maxLat - minLat, 0.01) * 1.5
        let lonDelta = max(maxLon - minLon, 0.01) * 1.5
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
        mapView.setRegion(region, animated: false)
    }

    private func makePreviewPolyline() -> MKPolyline? {
        guard let from = fromPlace, let to = toPlace else { return nil }
        var coords = [
            CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude),
            CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)
        ]
        return MKPolyline(coordinates: &coords, count: coords.count)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.85)
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let anno = annotation as? RoutePreviewMKAnnotation else { return nil }
            let id = "RoutePreviewAnnotation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: anno, reuseIdentifier: id)
            view.annotation = anno
            view.canShowCallout = true
            view.glyphImage = nil
            view.glyphText = nil
            switch anno.kind {
            case .start:
                view.markerTintColor = .systemBlue
                view.glyphText = "S"
            case .end:
                view.markerTintColor = .systemRed
                view.glyphText = "G"
            case .change:
                view.markerTintColor = .systemOrange
                view.glyphImage = UIImage(systemName: "exclamationmark.triangle.fill")
            }
            return view
        }
    }
}

private enum RoutePreviewAnnotationKind {
    case start
    case end
    case change
}

private struct RoutePreviewAnnotation: Identifiable {
    let id = UUID()
    let title: String
    let coordinate: CLLocationCoordinate2D
    let kind: RoutePreviewAnnotationKind

    var asAnnotation: RoutePreviewMKAnnotation {
        RoutePreviewMKAnnotation(title: title, coordinate: coordinate, kind: kind)
    }
}

private final class RoutePreviewMKAnnotation: NSObject, MKAnnotation {
    let title: String?
    let coordinate: CLLocationCoordinate2D
    let kind: RoutePreviewAnnotationKind

    init(title: String, coordinate: CLLocationCoordinate2D, kind: RoutePreviewAnnotationKind) {
        self.title = title
        self.coordinate = coordinate
        self.kind = kind
    }
}

#if canImport(GoogleMaps)
private extension MapPreview {
    var googleMapPreview: some View {
        GoogleMapPreview(
            fromPlace: fromPlace,
            toPlace: toPlace,
            fromName: fromName,
            toName: toName
        )
        .frame(height: 200)
        .cornerRadius(8)
    }
}

private struct GoogleMapPreview: UIViewRepresentable {
    let fromPlace: LatLng?
    let toPlace: LatLng?
    let fromName: String
    let toName: String
    
    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(latitude: 35.6812, longitude: 139.7671, zoom: 12)
        let options = GMSMapViewOptions()
        options.camera = camera
        let mapView = GMSMapView(options: options)
        mapView.isUserInteractionEnabled = false
        mapView.settings.setAllGesturesEnabled(false)
        updateMap(mapView)
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        updateMap(mapView)
    }
    
    private func updateMap(_ mapView: GMSMapView) {
        mapView.clear()
        var bounds = GMSCoordinateBounds()
        var hasBounds = false
        
        if let from = fromPlace {
            let coordinate = CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)
            let marker = GMSMarker(position: coordinate)
            marker.title = fromName
            marker.icon = GMSMarker.markerImage(with: UIColor.systemBlue)
            marker.map = mapView
            bounds = GMSCoordinateBounds(coordinate: coordinate, coordinate: coordinate)
            hasBounds = true
        }
        
        if let to = toPlace {
            let coordinate = CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)
            let marker = GMSMarker(position: coordinate)
            marker.title = toName
            marker.icon = GMSMarker.markerImage(with: UIColor.systemRed)
            marker.map = mapView
            if hasBounds {
                bounds = bounds.includingCoordinate(coordinate)
            } else {
                bounds = GMSCoordinateBounds(coordinate: coordinate, coordinate: coordinate)
                hasBounds = true
            }
        }
        
        if let from = fromPlace, let to = toPlace {
            let path = GMSMutablePath()
            path.addLatitude(from.latitude, longitude: from.longitude)
            path.addLatitude(to.latitude, longitude: to.longitude)
            let line = GMSPolyline(path: path)
            line.strokeWidth = 4
            line.strokeColor = UIColor.systemBlue
            line.map = mapView
        }
        
        if hasBounds {
            let update = GMSCameraUpdate.fit(bounds, withPadding: 32)
            mapView.moveCamera(update)
        } else {
            let camera = GMSCameraPosition(latitude: 35.6812, longitude: 139.7671, zoom: 12)
            mapView.camera = camera
        }
    }
}
#endif
