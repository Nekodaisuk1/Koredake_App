//
//  RouteRiskEvaluator.swift
//  Koredake
//
//  Created by Codex on 2025/11/08.
//

import Foundation
import MapKit

struct RouteRiskSummary {
    let score: Int
    let impact: Impact
    let tags: [String]
    let message: String
    let riskDetails: [RiskDetail]
    let wxRepresentative: WxFeature?
    let weatherScore: Int
    let timeScore: Int
    let scenarioScores: [String: Int]
}

struct RouteRiskSample: Identifiable {
    let id = UUID()
    let time: Date
    let coordinate: CLLocationCoordinate2D
    let mode: Mode
    let wx: WxFeature?
    let impact: Impact
}

struct RouteRiskDetail {
    let route: MKRoute
    let summary: RouteRiskSummary
    let samples: [RouteRiskSample]
}

private struct RouteScenario {
    let route: MKRoute
    let travelTime: TimeInterval
    let label: String
}

private struct SamplePoint {
    let time: Date
    let coordinate: CLLocationCoordinate2D
    let mode: Mode
    let dtMinutes: Int
    var wx: WxFeature?
}

protocol RouteProvider {
    func routes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: Mode) async throws -> [MKRoute]
}

final class MapKitRouteProvider: RouteProvider {
    func routes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: Mode) async throws -> [MKRoute] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = transportType(for: mode)
        request.requestsAlternateRoutes = true

        let directions = MKDirections(request: request)
        return try await withCheckedThrowingContinuation { continuation in
            directions.calculate { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: response?.routes ?? [])
            }
        }
    }

    private func transportType(for mode: Mode) -> MKDirectionsTransportType {
        switch mode {
        case .walk, .bike:
            return .walking
        case .train, .bus:
            return .transit
        }
    }
}

final class RouteRiskEvaluator {
    private let weather: WeatherClient
    private let rules: RuleEngine
    private let routeProvider: RouteProvider
    private let stepMinutes: Int
    private let alpha: Double
    private let beta: Double

    init(
        weather: WeatherClient,
        rules: RuleEngine = RuleEngine(),
        routeProvider: RouteProvider = MapKitRouteProvider(),
        stepMinutes: Int = 5,
        alpha: Double = 0.6,
        beta: Double = 0.4
    ) {
        self.weather = weather
        self.rules = rules
        self.routeProvider = routeProvider
        self.stepMinutes = stepMinutes
        self.alpha = alpha
        self.beta = beta
    }

    func evaluate(
        from: LatLng,
        to: LatLng,
        mode: Mode,
        departAt: Date,
        targetArrival: Date? = nil,
        rainAversion: Int
    ) async throws -> RouteRiskSummary? {
        let routes = try await routeProvider.routes(
            from: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude),
            to: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude),
            mode: mode
        )
        guard !routes.isEmpty else { return nil }

        let scenarios = buildScenarios(from: routes)
        var scenarioResults: [(scenario: RouteScenario, weatherScore: Double, timeScore: Double, totalScore: Double, samples: [SamplePoint])] = []

        for scenario in scenarios {
            var samples = samplePoints(for: scenario, departAt: departAt, mode: mode)
            samples = try await assignWeather(to: samples)

            let weatherScore = aggregateWeatherScore(from: samples, rainAversion: rainAversion)
            let timeScore = targetArrival.map { computeTimeRisk(arrivalTarget: $0, departAt: departAt, travelTime: scenario.travelTime) } ?? 0
            let totalScore = alpha * weatherScore + beta * timeScore
            scenarioResults.append((scenario, weatherScore, timeScore, totalScore, samples))
        }

        guard !scenarioResults.isEmpty else { return nil }
        return buildSummary(from: scenarioResults, mode: mode, rainAversion: rainAversion)
    }

    func detail(
        from: LatLng,
        to: LatLng,
        mode: Mode,
        departAt: Date,
        targetArrival: Date? = nil,
        rainAversion: Int
    ) async throws -> RouteRiskDetail? {
        let routes = try await routeProvider.routes(
            from: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude),
            to: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude),
            mode: mode
        )
        guard !routes.isEmpty else { return nil }

        let scenarios = buildScenarios(from: routes)
        var scenarioResults: [(scenario: RouteScenario, weatherScore: Double, timeScore: Double, totalScore: Double, samples: [SamplePoint])] = []

        for scenario in scenarios {
            var samples = samplePoints(for: scenario, departAt: departAt, mode: mode)
            samples = try await assignWeather(to: samples)

            let weatherScore = aggregateWeatherScore(from: samples, rainAversion: rainAversion)
            let timeScore = targetArrival.map { computeTimeRisk(arrivalTarget: $0, departAt: departAt, travelTime: scenario.travelTime) } ?? 0
            let totalScore = alpha * weatherScore + beta * timeScore
            scenarioResults.append((scenario, weatherScore, timeScore, totalScore, samples))
        }

        guard let s0 = scenarioResults.first else { return nil }

        let summary = buildSummary(from: scenarioResults, mode: mode, rainAversion: rainAversion)

        let samples: [RouteRiskSample] = s0.samples.map { sample in
            let impact: Impact
            if let wx = sample.wx {
                let matches = rules.matchingRules(mode: sample.mode, wx: wx, rainAversion: rainAversion)
                impact = rules.impactForMatches(matches)
            } else {
                impact = .low
            }
            return RouteRiskSample(
                time: sample.time,
                coordinate: sample.coordinate,
                mode: sample.mode,
                wx: sample.wx,
                impact: impact
            )
        }

        return RouteRiskDetail(route: s0.scenario.route, summary: summary, samples: samples)
    }

    private func buildSummary(
        from scenarioResults: [(scenario: RouteScenario, weatherScore: Double, timeScore: Double, totalScore: Double, samples: [SamplePoint])],
        mode: Mode,
        rainAversion: Int
    ) -> RouteRiskSummary {
        let s0 = scenarioResults[0]
        let s2 = scenarioResults.count > 2 ? scenarioResults[2] : s0
        let finalScore = max(s0.totalScore, s2.totalScore * 0.7)
        let impact = impactRank(for: finalScore)

        let (tags, message) = buildMessage(from: s0.samples, mode: mode, rainAversion: rainAversion, timeScore: s0.timeScore)
        let sampleWx = s0.samples.compactMap { $0.wx }
        let riskDetails = rules.riskDetails(mode: mode, travelHours: sampleWx, rainAversion: rainAversion)
        let representativeWx = s0.samples.compactMap { $0.wx }.first

        let scenarioScores = [
            "S0": Int(round(s0.totalScore)),
            "S1": scenarioResults.count > 1 ? Int(round(scenarioResults[1].totalScore)) : Int(round(s0.totalScore)),
            "S2": Int(round(s2.totalScore))
        ]

        return RouteRiskSummary(
            score: Int(round(finalScore)),
            impact: impact,
            tags: tags,
            message: message,
            riskDetails: riskDetails,
            wxRepresentative: representativeWx,
            weatherScore: Int(round(s0.weatherScore)),
            timeScore: Int(round(s0.timeScore)),
            scenarioScores: scenarioScores
        )
    }

    private func buildScenarios(from routes: [MKRoute]) -> [RouteScenario] {
        let sorted = routes.sorted { $0.expectedTravelTime < $1.expectedTravelTime }
        let r0 = sorted.first!
        let r1 = sorted.count > 1 ? sorted[1] : r0

        let t0 = r0.expectedTravelTime
        let t1 = r1.expectedTravelTime
        let delta = max(t1 - t0, 0)
        let t2 = t1 + delta

        return [
            RouteScenario(route: r0, travelTime: t0, label: "S0"),
            RouteScenario(route: r1, travelTime: t1, label: "S1"),
            RouteScenario(route: r0, travelTime: t2, label: "S2")
        ]
    }

    private func samplePoints(for scenario: RouteScenario, departAt: Date, mode: Mode) -> [SamplePoint] {
        let stepSeconds = TimeInterval(stepMinutes * 60)
        let totalSeconds = max(scenario.travelTime, stepSeconds)
        let steps = max(1, Int(ceil(totalSeconds / stepSeconds)))

        var samples: [SamplePoint] = []
        for j in 0...steps {
            let elapsed = min(TimeInterval(j) * stepSeconds, scenario.travelTime)
            let ratio = scenario.travelTime > 0 ? min(elapsed / scenario.travelTime, 1.0) : 0
            let distance = scenario.route.distance * ratio
            let coord = scenario.route.polyline.coordinate(atMeters: distance)
            let time = departAt.addingTimeInterval(elapsed)
            let stepMode = modeForDistance(distance, in: scenario.route, fallback: mode)
            samples.append(SamplePoint(time: time, coordinate: coord, mode: stepMode, dtMinutes: stepMinutes, wx: nil))
        }
        return samples
    }

    private struct LocationBucket: Hashable {
        let lat: Double
        let lon: Double
    }

    private func assignWeather(to samples: [SamplePoint]) async throws -> [SamplePoint] {
        guard !samples.isEmpty else { return samples }

        let bucketed = Dictionary(grouping: samples) { sample in
            let precision = 0.01
            let lat = (sample.coordinate.latitude / precision).rounded() * precision
            let lon = (sample.coordinate.longitude / precision).rounded() * precision
            return LocationBucket(lat: lat, lon: lon)
        }

        var weatherByBucket: [LocationBucket: [WxFeature]] = [:]

        try await withThrowingTaskGroup(of: (LocationBucket, [WxFeature]).self) { group in
            for (bucket, points) in bucketed {
                group.addTask {
                    let times = points.map { $0.time }
                    let minTime = times.min() ?? Date()
                    let maxTime = times.max() ?? minTime
                    let startISO = self.iso8601UTC(minTime.addingTimeInterval(-30 * 60))
                    let endISO = self.iso8601UTC(maxTime.addingTimeInterval(30 * 60))
                    let data = try await self.weather.hourly(
                        lat: bucket.lat,
                        lon: bucket.lon,
                        startISO: startISO,
                        endISO: endISO
                    )
                    return (bucket, data)
                }
            }

            for try await result in group {
                weatherByBucket[result.0] = result.1
            }
        }

        var enriched: [SamplePoint] = []
        enriched.reserveCapacity(samples.count)

        for sample in samples {
            let precision = 0.01
            let lat = (sample.coordinate.latitude / precision).rounded() * precision
            let lon = (sample.coordinate.longitude / precision).rounded() * precision
            let bucket = LocationBucket(lat: lat, lon: lon)
            guard let bucketWeather = weatherByBucket[bucket] else {
                enriched.append(sample)
                continue
            }
            var copy = sample
            copy.wx = nearestWeather(to: sample.time, in: bucketWeather)
            enriched.append(copy)
        }

        return enriched
    }

    private func nearestWeather(to time: Date, in list: [WxFeature]) -> WxFeature? {
        guard !list.isEmpty else { return nil }
        return list.min {
            abs((parseISO8601($0.timeISO) ?? time).timeIntervalSince(time)) <
            abs((parseISO8601($1.timeISO) ?? time).timeIntervalSince(time))
        }
    }

    private func aggregateWeatherScore(from samples: [SamplePoint], rainAversion: Int) -> Double {
        var sum = 0.0
        var denom = 0.0

        for sample in samples {
            guard let wx = sample.wx else { continue }
            let weight = modeWeight(for: sample.mode)
            let matches = rules.matchingRules(mode: sample.mode, wx: wx, rainAversion: rainAversion)
            let impact = rules.impactForMatches(matches)
            let base = impactScore(for: impact)
            let dt = Double(sample.dtMinutes)
            sum += base * weight * dt
            denom += weight * dt
        }

        guard denom > 0 else { return 0 }
        return min(max(sum / denom, 0), 100)
    }

    private func buildMessage(from samples: [SamplePoint], mode: Mode, rainAversion: Int, timeScore: Double) -> ([String], String) {
        var tagWeights: [String: Double] = [:]
        for sample in samples {
            guard let wx = sample.wx else { continue }
            let matches = rules.matchingRules(mode: mode, wx: wx, rainAversion: rainAversion)
            for match in matches {
                tagWeights[match.id, default: 0] += Double(sample.dtMinutes)
            }
        }

        let sortedTags = rules.reduceCompatibleTags(tagWeights: tagWeights)
        let primaryTags = Array(sortedTags.prefix(2))

        var parts: [String] = []
        for tag in primaryTags {
            if let msg = rules.message(for: tag) {
                let head = msg.split(separator: "。").first.map(String.init) ?? msg
                parts.append(head)
            }
        }

        if timeScore >= 70 {
            parts.append("到着マージン小。早め出発を")
        } else if timeScore >= 40 {
            parts.append("到着マージン要注意")
        }

        let message = parts.isEmpty ? "概ね良好" : parts.joined(separator: "／")
        return (primaryTags, message)
    }

    private func computeTimeRisk(arrivalTarget: Date, departAt: Date, travelTime: TimeInterval) -> Double {
        let arrival = departAt.addingTimeInterval(travelTime)
        let margin = arrivalTarget.timeIntervalSince(arrival) / 60.0
        if margin < 0 { return 100 }
        if margin < 5 { return 80 + (5 - margin) * 4 }
        if margin < 10 { return 40 + (10 - margin) * 8 }
        return max(0, 40 - (margin - 10) * 2)
    }

    private func impactScore(for impact: Impact) -> Double {
        switch impact {
        case .low: return 30
        case .mid: return 60
        case .high: return 90
        }
    }

    private func impactRank(for score: Double) -> Impact {
        if score >= 67 { return .high }
        if score >= 34 { return .mid }
        return .low
    }

    private func modeWeight(for mode: Mode?) -> Double {
        switch mode {
        case .walk, .bike:
            return 1.0
        case .bus:
            return 0.5
        case .train:
            return 0.25
        case .none:
            return 1.0
        }
    }

    private func modeForDistance(_ distance: CLLocationDistance, in route: MKRoute, fallback: Mode) -> Mode {
        var cumulative: CLLocationDistance = 0
        for step in route.steps {
            let stepDistance = max(step.distance, 0)
            cumulative += stepDistance
            if distance <= cumulative {
                return modeFromTransport(step.transportType, fallback: fallback)
            }
        }
        return fallback
    }

    private func modeFromTransport(_ transport: MKDirectionsTransportType, fallback: Mode) -> Mode {
        if transport.contains(.walking) {
            return .walk
        }
        if transport.contains(.transit) {
            return .train
        }
        if transport.contains(.automobile) {
            return .bus
        }
        return fallback
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

    private func iso8601UTC(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private extension MKPolyline {
    func coordinate(atMeters distance: CLLocationDistance) -> CLLocationCoordinate2D {
        let count = pointCount
        guard count > 0 else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        let points = self.points()
        if count == 1 { return points[0].coordinate }

        var remaining = distance
        for i in 0..<(count - 1) {
            let p1 = points[i]
            let p2 = points[i + 1]
            let segment = p1.distance(to: p2)
            if remaining <= segment {
                let ratio = segment > 0 ? remaining / segment : 0
                let x = p1.x + (p2.x - p1.x) * ratio
                let y = p1.y + (p2.y - p1.y) * ratio
                return MKMapPoint(x: x, y: y).coordinate
            }
            remaining -= segment
        }
        return points[count - 1].coordinate
    }
}
