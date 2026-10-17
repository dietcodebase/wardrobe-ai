import SwiftUI
import UniformTypeIdentifiers

struct ModelStatusView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var manager: ModelManager
    @ObservedObject var store: WardrobeStore
    @State private var importingDescriptor: ModelDescriptor?
    @State private var occasion = "Everyday"
    @State private var anchorItemID: UUID?
    @State private var message: String?
    @AppStorage("weather-city") private var weatherCity = ""
    @State private var weatherState = WeatherContextState.unavailable(reason: "Choose a city to add optional weather context.")
    @State private var weatherRefreshTask: Task<Void, Never>?
    private let weatherService = WeatherContextService(provider: OpenWeatherMapProvider())

    private var suggestions: [OutfitSuggestion] {
        (try? store.recommendations(for: occasion == "Everyday" ? nil : occasion, anchorItemID: anchorItemID, weather: weatherState.isCurrent ? weatherState.snapshot : nil)) ?? []
    }

    var body: some View {
        List {
            Section {
                Label("Manual wardrobe is available without a model.", systemImage: "checkmark.circle")
                    .accessibilityIdentifier("manual-wardrobe-status")
                Label("Imported and downloaded models are verified before they are stored.", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Local AI status")
            }

            Section("Pinned candidates") {
                ForEach(ModelDescriptor.qualifiedCandidates) { descriptor in
                    modelRow(descriptor)
                }
            }

            if let message = manager.provisioningMessage {
                Section { Text(message).foregroundStyle(.secondary) }
            }

            Section("What should I wear?") {
                Picker("Occasion", selection: $occasion) {
                    ForEach(GarmentTaxonomy.occasions, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                Picker("What goes with this?", selection: $anchorItemID) {
                    Text("Any garment").tag(Optional<UUID>.none)
                    ForEach(store.allGarments) { item in
                        Text(item.name).tag(Optional(item.id))
                    }
                }
                .pickerStyle(.menu)
                if suggestions.isEmpty {
                    Text("Add a garment to receive owned-item suggestions.").foregroundStyle(.secondary)
                } else {
                    ForEach(suggestions.prefix(3)) { suggestion in
                        suggestionRow(suggestion)
                    }
                }
                weatherContext
                Text("Calendar remains manual context until M11.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .alert("Outfit suggestion", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(message ?? "") }
        .fileImporter(isPresented: Binding(
            get: { importingDescriptor != nil },
            set: { if !$0 { importingDescriptor = nil } }
        ), allowedContentTypes: [.data]) { result in
            guard let descriptor = importingDescriptor else { return }
            importingDescriptor = nil
            switch result {
            case let .success(url): manager.importModel(at: url, descriptor: descriptor)
            case let .failure(error): manager.reportProvisioningFailure(error)
            }
        }
        .task {
            guard !weatherCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if let cached = await weatherService.cachedState(for: WeatherLocation(city: weatherCity)) { weatherState = cached }
        }
        .task(id: weatherState.snapshot?.fetchedAt) {
            while !Task.isCancelled {
                weatherState = await weatherService.currentState(from: weatherState)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { weatherState = await weatherService.currentState(from: weatherState) }
        }
        .onDisappear { weatherRefreshTask?.cancel() }
    }

    @ViewBuilder
    private func modelRow(_ descriptor: ModelDescriptor) -> some View {
        let status = manager.downloads?.statusByModel[descriptor.id] ?? .notPresent
        VStack(alignment: .leading, spacing: 8) {
            Text(descriptor.id.rawValue.uppercased()).font(.headline)
            Text(ByteCountFormatter.string(fromByteCount: descriptor.expectedBytes, countStyle: .file))
                .font(.caption).foregroundStyle(.secondary)
            Text(statusDescription(status)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Import") { importingDescriptor = descriptor }
                Button(downloadTitle(status)) { downloadAction(descriptor, status: status) }
                if case .downloading = status { Button("Cancel", role: .cancel) { manager.downloads?.cancel(descriptor) } }
            }
            .buttonStyle(.bordered)
            .disabled(!ModelRuntimePolicy.deviceQualificationPassed || manager.downloads == nil || isDownloading(status))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(descriptor.id.rawValue) model: \(statusDescription(status))")
    }

    private func statusDescription(_ status: ModelTransferStatus) -> String {
        switch status {
        case .notPresent: "Not installed"
        case let .downloading(progress): "Downloading \(Int(progress * 100)) percent"
        case .interrupted: "Download interrupted; resume is available"
        case .available: "Verified and ready for a configured runtime"
        case let .failed(message): "Download failed: \(message)"
        }
    }

    private func downloadTitle(_ status: ModelTransferStatus) -> String {
        if case .interrupted = status { return "Resume" }
        return "Download"
    }

    private func isDownloading(_ status: ModelTransferStatus) -> Bool {
        if case .downloading = status { return true }
        return false
    }

    private func downloadAction(_ descriptor: ModelDescriptor, status: ModelTransferStatus) {
        if case .interrupted = status { manager.downloads?.resume(descriptor) }
        else { manager.downloads?.download(descriptor) }
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: OutfitSuggestion) -> some View {
        let names = suggestion.itemIDs.compactMap { store.item(id: $0)?.name }
        VStack(alignment: .leading, spacing: 8) {
            Text(names.joined(separator: " · ")).font(.headline)
            Text(suggestion.explanation).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Save outfit") { save(suggestion) }
                Button("Wear today") { wear(suggestion) }
            }
            .buttonStyle(.bordered)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggestion: \(names.joined(separator: ", ")). \(suggestion.explanation)")
    }

    private func save(_ suggestion: OutfitSuggestion) {
        do { _ = try store.saveSuggestion(suggestion); message = "Saved to your outfits. Wear is recorded only when you choose Wear today." }
        catch { message = error.localizedDescription }
    }

    private func wear(_ suggestion: OutfitSuggestion) {
        do { _ = try store.wearSuggestion(suggestion); message = "Recorded as worn today." }
        catch { message = error.localizedDescription }
    }

    @ViewBuilder
    private var weatherContext: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Optional weather context").font(.headline)
            HStack {
                TextField("City", text: $weatherCity).textInputAutocapitalization(.words)
                Button("Refresh", action: refreshWeather)
                .disabled(weatherCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(weatherDescription).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Optional weather context. \(weatherDescription)")
    }

    private var weatherDescription: String {
        switch weatherState {
        case let .fresh(snapshot): return "Current from OpenWeatherMap: \(snapshot.description), \(Int(snapshot.temperatureCelsius.rounded()))°C in \(snapshot.location.normalizedCity)."
        case let .cached(snapshot): return "Cached weather: \(snapshot.description), \(Int(snapshot.temperatureCelsius.rounded()))°C in \(snapshot.location.normalizedCity)."
        case let .stale(snapshot, reason): return "Stale weather: \(snapshot.description), \(Int(snapshot.temperatureCelsius.rounded()))°C in \(snapshot.location.normalizedCity). \(reason) Recommendations are not adjusted."
        case let .unavailable(reason): return "Weather unavailable: \(reason) Recommendations remain usable without it."
        }
    }

    private func refreshWeather() {
        weatherRefreshTask?.cancel()
        let location = WeatherLocation(city: weatherCity)
        let requestedCity = location.normalizedCity
        weatherRefreshTask = Task {
            let state = await weatherService.refresh(location: location)
            guard !Task.isCancelled,
                  weatherCity.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(requestedCity) == .orderedSame
            else { return }
            weatherState = state
        }
    }
}
