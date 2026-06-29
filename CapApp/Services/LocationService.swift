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

    /// Geofencing relaunches the app in the background, which needs "Always" authorization.
    func requestAlwaysAccess() {
        manager.requestAlwaysAuthorization()
    }

    var hasAccess: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var hasAlwaysAccess: Bool {
        authorizationStatus == .authorizedAlways
    }

    // MARK: - Geofencing

    /// Replace the monitored set with the user's saved places (capped at iOS's 20-region limit).
    func startMonitoring(_ places: [Place]) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        for place in places.prefix(20) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                radius: place.radius,
                identifier: place.id.uuidString
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    func stopAllMonitoring() {
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
    }

    /// Resolve a region identifier back to the place's display name.
    private func placeName(for identifier: String) -> String? {
        LocalStore.shared.loadPlaces().first { $0.id.uuidString == identifier }?.name
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

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            let name = self.placeName(for: region.identifier) ?? "a saved place"
            NotificationService.shared.postNow(title: "Arrived at \(name)", body: "You're here.")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            let name = self.placeName(for: region.identifier) ?? "a saved place"
            NotificationService.shared.postNow(title: "Left \(name)", body: "Heading out.")
        }
    }

    private func resumeContinuations(with location: CLLocation?) {
        let pending = locationContinuations
        locationContinuations.removeAll()
        for continuation in pending { continuation.resume(returning: location) }
    }
}
