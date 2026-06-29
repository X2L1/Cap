import MapKit
import SwiftUI

/// Manage geofenced key places and toggle arrival/departure alerts.
struct PlacesView: View {
    @ObservedObject var locationService: LocationService

    @State private var places: [Place] = LocalStore.shared.loadPlaces()
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @AppStorage("cap.geofencing.enabled") private var monitoringEnabled = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Alert me on arrival & departure", isOn: $monitoringEnabled)
                        .onChange(of: monitoringEnabled) { _, on in handleToggle(on) }
                    if monitoringEnabled && !locationService.hasAlwaysAccess {
                        Text("Needs \"Always\" location access to alert you in the background. Grant it in Settings → Cap → Location.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Geofencing relaunches Cap in the background when you cross a place's boundary. iOS allows up to 20 places.")
                }

                Section("Add a place") {
                    HStack {
                        TextField("Search (dorm, library, gym…)", text: $query)
                            .onSubmit { Task { await runSearch() } }
                        if searching { ProgressView() }
                    }
                    ForEach(results, id: \.self) { item in
                        Button {
                            add(item)
                        } label: {
                            Label(item.name ?? "Unknown", systemImage: "plus.circle")
                        }
                        .disabled(places.count >= 20)
                    }
                }

                Section("Saved places") {
                    if places.isEmpty {
                        Text("None yet.").foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(places) { place in
                            Label(place.name, systemImage: "mappin.circle.fill")
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Key places")
        }
    }

    private func runSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        results = await locationService.search(query)
        searching = false
    }

    private func add(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        let place = Place(name: item.name ?? "Place",
                          latitude: coord.latitude, longitude: coord.longitude)
        places.append(place)
        LocalStore.shared.savePlaces(places)
        query = ""
        results = []
        if monitoringEnabled { locationService.startMonitoring(places) }
    }

    private func delete(at offsets: IndexSet) {
        places.remove(atOffsets: offsets)
        LocalStore.shared.savePlaces(places)
        if monitoringEnabled { locationService.startMonitoring(places) }
    }

    private func handleToggle(_ on: Bool) {
        if on {
            locationService.requestAlwaysAccess()
            locationService.startMonitoring(places)
        } else {
            locationService.stopAllMonitoring()
        }
    }
}
