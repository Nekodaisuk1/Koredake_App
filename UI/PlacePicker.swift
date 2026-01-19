//
//  PlacePicker.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import SwiftUI
import MapKit

struct Place: Equatable, Identifiable {
    let name: String
    let address: String
    let coordinate: LatLng
    let id: String
    
    init(name: String, address: String, coordinate: LatLng) {
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.id = name + "|" + address
    }
}

@MainActor
struct PlacePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedPlace: Place?
    let placeholder: String
    
    @State private var searchText = ""
    @State private var places: [Place] = []
    @State private var isSearching = false
    
    // Apple Maps ベースの UI に統一
    var body: some View {
        appleMapsPicker
    }
    
    // Apple Maps 用 Picker
    private var appleMapsPicker: some View {
        NavigationView {
            VStack(spacing: 12) {
                HStack {
                    TextField(placeholder, text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: searchText) { _ in updateQuery() }
                        .onSubmit { performSearch(usingFirstPrediction: false) }
                    if !searchText.isEmpty {
                        Button(role: .destructive) { searchText = ""; places.removeAll() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                if isSearching {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if completerResults.isEmpty && !searchText.isEmpty {
                    Text("検索結果がありません")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(completerResults.indices, id: \.self) { idx in
                            let completion = completerResults[idx]
                            Button {
                                resolveCompletion(completion)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(completion.title).font(.headline)
                                    Text(completion.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("場所を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    // MARK: - MapKit Search
    private let completer = MKLocalSearchCompleter()
    @State private var completerResults: [MKLocalSearchCompletion] = []
    // Retain delegate strongly (MKLocalSearchCompleter holds a weak delegate)
    @State private var completerDelegateRef: CompleterDelegate?

    private func updateQuery() {
        guard !searchText.isEmpty else {
            completerResults = []
            places.removeAll()
            return
        }
        // Ensure delegate is retained
        if completer.delegate == nil {
            let d = CompleterDelegate { results in
                self.completerResults = results
            }
            completerDelegateRef = d
            completer.delegate = d
        }

        completer.queryFragment = searchText
        completer.resultTypes = [.pointOfInterest, .address]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
            span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
        )
    }

    private func performSearch(usingFirstPrediction: Bool) {
        let target: MKLocalSearchCompletion?
        if usingFirstPrediction {
            target = completerResults.first
        } else {
            target = nil // Do nothing, rely on user tap
        }
        guard let completion = target else { return }
        let request = MKLocalSearch.Request(completion: completion)
        isSearching = true
        MKLocalSearch(request: request).start { response, error in
            defer { isSearching = false }
            guard let item = response?.mapItems.first else { return }
            if let coordinate = item.placemark.location?.coordinate {
                let place = Place(
                    name: item.name ?? completion.title,
                    address: item.placemark.title ?? completion.subtitle,
                    coordinate: LatLng(latitude: coordinate.latitude, longitude: coordinate.longitude)
                )
                selectedPlace = place
                dismiss()
            }
        }
    }

    // Resolve a user-tapped completion to concrete coordinates
    private func resolveCompletion(_ completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        isSearching = true
        MKLocalSearch(request: request).start { response, error in
            defer { isSearching = false }
            if let item = response?.mapItems.first, let coord = item.placemark.location?.coordinate {
                print("🔎 resolveCompletion: found coordinate for \(completion.title): \(coord.latitude), \(coord.longitude)")
                let place = Place(
                    name: item.name ?? completion.title,
                    address: item.placemark.title ?? completion.subtitle,
                    coordinate: LatLng(latitude: coord.latitude, longitude: coord.longitude)
                )
                selectedPlace = place
                dismiss()
            } else {
                print("🔎 resolveCompletion: failed to resolve coordinates for \(completion.title); response: \(String(describing: response)), error: \(String(describing: error))")
                // If resolution fails, fallback to a place with no coordinates (caller should handle)
                let fallback = Place(name: completion.title, address: completion.subtitle, coordinate: LatLng(latitude: 0, longitude: 0))
                selectedPlace = fallback
                dismiss()
            }
        }
    }
}

// MKLocalSearchCompleter delegate bridge
private final class CompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    let onUpdate: ([MKLocalSearchCompletion]) -> Void
    init(onUpdate: @escaping ([MKLocalSearchCompletion]) -> Void) { self.onUpdate = onUpdate }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onUpdate(completer.results)
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("❌ MKLocalSearchCompleter error: \(error.localizedDescription)")
        onUpdate([])
    }
}

