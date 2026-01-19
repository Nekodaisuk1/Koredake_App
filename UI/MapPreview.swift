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
    let fromName: String
    let toName: String
    
    var body: some View {
        // Apple Maps (MapKit) を常に使用
        mapKitPreview
    }
    
    private var mapKitPreview: some View {
        MapKitPreview(
            fromPlace: fromPlace,
            toPlace: toPlace,
            fromName: fromName,
            toName: toName
        )
        .frame(height: 200)
        .cornerRadius(8)
    }
}

private struct MapKitPreview: View {
    let fromPlace: LatLng?
    let toPlace: LatLng?
    let fromName: String
    let toName: String
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: annotations) { annotation in
            MapMarker(
                coordinate: annotation.coordinate,
                tint: annotation.isFrom ? .blue : .red
            )
        }
        .id("\(fromPlace?.latitude ?? 0)-\(fromPlace?.longitude ?? 0)-\(toPlace?.latitude ?? 0)-\(toPlace?.longitude ?? 0)")
        .onAppear(perform: updateRegion)
        .onChange(of: fromPlace?.latitude ?? 0) { _ in updateRegion() }
        .onChange(of: fromPlace?.longitude ?? 0) { _ in updateRegion() }
        .onChange(of: toPlace?.latitude ?? 0) { _ in updateRegion() }
        .onChange(of: toPlace?.longitude ?? 0) { _ in updateRegion() }
    }
    
    private var annotations: [MapAnnotation] {
        var items: [MapAnnotation] = []
        if let from = fromPlace {
            items.append(MapAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude),
                title: fromName,
                isFrom: true
            ))
        }
        if let to = toPlace {
            items.append(MapAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude),
                title: toName,
                isFrom: false
            ))
        }
        return items
    }
    
    private func updateRegion() {
        guard let from = fromPlace, let to = toPlace else {
            let target = fromPlace ?? toPlace
            if let coordinate = target.map({ CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }) {
                region = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
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
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}

private struct MapAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
    let isFrom: Bool
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
        let mapView = GMSMapView(frame: .zero)
        mapView.camera = camera
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
            if hasBounds {
                bounds = bounds.includingCoordinate(coordinate)
            } else {
                bounds = GMSCoordinateBounds(coordinate: coordinate, coordinate: coordinate)
                hasBounds = true
            }
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

