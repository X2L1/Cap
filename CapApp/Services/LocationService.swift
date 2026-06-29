import CoreLocation
import Foundation
import MapKit

/// Location + travel-time for "leave by" estimates. Foreground, on-demand — not live
/// tracking (that's not a real third-party iOS capability, per the roadmap). Current
/// location goes only to Apple's own MapKit routing service for ETA math.
@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var current: CLLocation?

    private let manager = CLLocationManager()
    private var locationContinuations: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        authorizationStatus = .notDetermined
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    var hasAccess: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// One-shot current location.
    func currentLocation() async -> CLLocation? {
        guard hasAccess else { return nil }
        if let current { return current }
        return await withCheckedContinuation { continuation in
            locationContinuations.append(continuation)
            manager.requestLocation()
        }
    }

    /// Search Apple Maps for a place query (e.g. "Evans Library").
    func search(_ query: String) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let current { request.region = MKCoordinateRegion(center: current.coordinate,
                                                             latitudinalMeters: 50_000, longitudinalMeters: 50_000) }
        let search = MKLocalSearch(request: request)
        return (try? await search.start())?.mapItems ?? []
    }

    /// Estimated travel time (seconds) from current location to a destination.
    func travelTime(to destination: MKMapItem, by transport: MKDirectionsTransportType = .automobile) async -> TimeInterval? {
        guard let current = await currentLocation() else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate))
        request.destination = destination
        request.transportType = transport
        let response = try? await MKDirections(request: request).calculateETA()
        return response?.expectedTravelTime
    }

    /// When to leave to arrive by `arrival`, given current travel time. Nil if no route.
    func leaveBy(arrival: Date, destination: MKMapItem, by transport: MKDirectionsTransportType = .automobile) async -> (leaveAt: Date, travel: TimeInterval)? {
        guard let travel = await travelTime(to: destination, by: transport) else { return nil }
        return (arrival.addingTimeInterval(-travel), travel)
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationStatus = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.current = location
            self.resumeContinuations(with: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resumeContinuations(with: nil) }
    }

    private func resumeContinuations(with location: CLLocation?) {
        let pending = locationContinuations
        locationContinuations.removeAll()
        for continuation in pending { continuation.resume(returning: location) }
    }
}
