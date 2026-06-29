import MapKit
import SwiftUI

/// SwiftUI's Picker needs a Hashable selection; MKDirectionsTransportType is an OptionSet,
/// not Hashable, so we wrap the three modes we offer.
enum TransportMode: String, CaseIterable, Identifiable {
    case drive, walk, transit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .drive: return "Drive"
        case .walk: return "Walk"
        case .transit: return "Transit"
        }
    }
    var directionsType: MKDirectionsTransportType {
        switch self {
        case .drive: return .automobile
        case .walk: return .walking
        case .transit: return .transit
        }
    }
}

/// "When do I need to leave?" — search a destination, set an arrival time, get a departure
/// time from Apple Maps routing. Foreground, on-demand.
struct LeaveByView: View {
    @ObservedObject var locationService: LocationService

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selected: MKMapItem?
    @State private var arrival = Date().addingTimeInterval(3600)
    @State private var transport: TransportMode = .drive
    @State private var result: (leaveAt: Date, travel: TimeInterval)?
    @State private var computing = false
    @State private var searching = false

    var body: some View {
        NavigationStack {
            Form {
                if !locationService.hasAccess {
                    Section {
                        Button("Allow location access") { locationService.requestAccess() }
                        Text("Cap needs your location to estimate travel time. It's used only for the routing request to Apple Maps.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Destination") {
                    HStack {
                        TextField("Search a place", text: $query)
                            .onSubmit { Task { await runSearch() } }
                        if searching { ProgressView() }
                    }
                    ForEach(results, id: \.self) { item in
                        Button {
                            selected = item
                            results = []
                            query = item.name ?? "Destination"
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.name ?? "Unknown").foregroundStyle(.primary)
                                if let title = item.placemark.title {
                                    Text(title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("When") {
                    DatePicker("Arrive by", selection: $arrival)
                    Picker("By", selection: $transport) {
                        ForEach(TransportMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        Task { await compute() }
                    } label: {
                        HStack {
                            Text(computing ? "Calculating…" : "When do I leave?")
                            if computing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(selected == nil || computing)

                    if let result {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Leave by \(result.leaveAt.formatted(date: .omitted, time: .shortened))")
                                .font(.headline).foregroundStyle(Theme.accent)
                            Text("\(Int(result.travel / 60)) min \(transportLabel)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Leave by")
        }
    }

    private var transportLabel: String {
        switch transport {
        case .walk: return "walk"
        case .transit: return "by transit"
        case .drive: return "drive"
        }
    }

    private func runSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        results = await locationService.search(query)
        searching = false
    }

    private func compute() async {
        guard let selected else { return }
        computing = true
        result = await locationService.leaveBy(arrival: arrival, destination: selected, by: transport.directionsType)
        computing = false
    }
}
