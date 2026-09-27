// Revision 4, F6 — Yer düzenle (07 §9.1, §9.8): name, aliases, "Şu anki konumu kaydet", radius chips, map link,
// "Konumu sil" / "Yeri sil" and the open items bound to this place. Edits go through store.upsertPlace; the name
// and aliases are committed on submit, focus loss and onDisappear. Coordinates are never logged.
import SwiftUI
import AsistCore

@MainActor
struct PlaceEditorView: View {
    let placeID: UUID

    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var nameDraft = ""
    @State private var aliasDraft = ""
    @State private var draftsLoaded = false
    @State private var locating = false
    @State private var showDeleteConfirm = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, aliases
    }

    /// Explicit: private @State/@FocusState/@Environment storage must not narrow the memberwise initializer
    /// (RouteDestination constructs this view).
    init(placeID: UUID) {
        self.placeID = placeID
    }

    var body: some View {
        Group {
            if let place = store.place(placeID) {
                editor(place)
            } else {
                EmptyStateView(title: "Yer bulunamadı",
                               message: "Bu yer silinmiş ya da artık mevcut değil.",
                               systemImage: "mappin.slash")
            }
        }
        .navigationTitle(store.place(placeID)?.name ?? "Yer")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Layout

    private func editor(_ place: Place) -> some View {
        let configured = LocationPlanner.isConfigured(place)
        let statusText: String = configured ? "Kayıtlı · " + LocationPlanner.radiusLabel(place.radiusMeters)
                                            : "Konum kaydedilmedi"
        let saveTitle: String = configured ? "Konumu buradan güncelle" : "Şu anki konumu kaydet"
        let now = Date()
        let items = boundItems()
        return List {
            Section {
                HStack(spacing: 12) {
                    Text("Ad")
                    Spacer(minLength: 8)
                    TextField("Örn: Fabrika", text: $nameDraft)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil
                        }
                }
                .frame(minHeight: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diğer adlar")
                    TextField("Örn: saha, tesis", text: $aliasDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .aliases)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil
                        }
                        .frame(minHeight: 36)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("“Fabrikaya varınca…”, “sahadan çıkınca…” derken bu adlardan biri geçerse bu yer kullanılır. Adları virgülle ayır.")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: configured ? "mappin.circle.fill" : "mappin.slash")
                        .font(.title3)
                        .foregroundStyle(configured ? Color.asistAccent : Color.orange)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusText)
                            .font(.body.weight(.medium))
                            .foregroundStyle(configured ? Color.primary : Color.orange)
                        if configured {
                            Text(coordinateText(place))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Color.secondary)
                                .textSelection(.enabled)
                        } else {
                            Text("Bu yerdeyken aşağıdaki düğmeye dokun.")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                .frame(minHeight: 52)
                if configured, let url = mapsURL(place) {
                    Link(destination: url) {
                        Label("Haritada aç", systemImage: "map")
                            .frame(minHeight: 44)
                    }
                }
            } header: {
                SectionHeader(title: "KONUM")
            }

            Section {
                Button {
                    saveCurrentLocation()
                } label: {
                    if locating {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(Color.white)
                            Text("Konum alınıyor…")
                        }
                    } else {
                        Label(saveTitle, systemImage: "location.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(locating)
            } footer: {
                Text(saveFooter(configured: configured))
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            Section {
                ChipRow {
                    ForEach(LocationPlanner.radiusChoices, id: \.self) { radius in
                        Chip(title: LocationPlanner.radiusLabel(radius),
                             isSelected: isSelectedRadius(radius, place: place)) {
                            setRadius(radius)
                        }
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                SectionHeader(title: "YARIÇAP")
            } footer: {
                Text("Bu mesafeye girince (ya da çıkınca) hatırlatırım. Büyük tesislerde 250 m veya üstü daha güvenilir.")
            }

            Section {
                if configured {
                    Button {
                        clearCoordinates()
                    } label: {
                        Label("Konumu sil", systemImage: "location.slash")
                            .frame(minHeight: 44)
                    }
                }
                Button(role: .destructive) {
                    focusedField = nil
                    showDeleteConfirm = true
                } label: {
                    Label("Yeri sil", systemImage: "trash")
                        .frame(minHeight: 44)
                }
            }

            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        ListItemLink(item: item, projectName: store.projectName(for: item), now: now)
                    }
                } header: {
                    SectionHeader(title: "BU YERE BAĞLI İŞLER", count: items.count)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Bu yer silinsin mi? Bağlı hatırlatmaların yeri kaldırılır.",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Yeri sil", role: .destructive) {
                deletePlace()
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .onAppear {
            loadDrafts(place)
        }
        .onDisappear {
            commitAll()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .name && newValue != .name { commitName() }
            if oldValue == .aliases && newValue != .aliases { commitAliases() }
        }
        .onChange(of: nameDraft) { _, newValue in
            if newValue.contains("\n") {
                nameDraft = newValue.replacingOccurrences(of: "\n", with: " ")
                focusedField = nil
            }
        }
    }

    // MARK: - Texts

    private func coordinateText(_ place: Place) -> String {
        LocationPlanner.coordinateText(place.latitude) + ", " + LocationPlanner.coordinateText(place.longitude)
    }

    private func saveFooter(configured: Bool) -> String {
        if configured {
            return "Konum yanlışsa o yerdeyken yeniden kaydet. Açık alanda daha doğru olur."
        }
        return "Bu yerdeyken dokun; Asist konumunu kaydeder. Konumun yalnız bu iPhone'da kalır."
    }

    /// https://maps.apple.com/?ll=<lat>,<lon>&q=<name> (URLComponents escapes the name).
    private func mapsURL(_ place: Place) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        let coordinate = LocationPlanner.coordinateText(place.latitude, decimals: 6) + ","
            + LocationPlanner.coordinateText(place.longitude, decimals: 6)
        components.queryItems = [URLQueryItem(name: "ll", value: coordinate),
                                 URLQueryItem(name: "q", value: place.name.isEmpty ? "Yer" : place.name)]
        return components.url
    }

    private func isSelectedRadius(_ radius: Double, place: Place) -> Bool {
        abs(LocationPlanner.clampedRadius(place.radiusMeters) - radius) < 0.5
    }

    /// Open items bound to this place, oldest first.
    private func boundItems() -> [Item] {
        let bound = store.items.filter { (item: Item) -> Bool in
            item.isOpen && item.placeID == placeID
        }
        return bound.sorted { (lhs: Item, rhs: Item) -> Bool in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - Drafts

    private func loadDrafts(_ place: Place) {
        guard !draftsLoaded else { return }
        nameDraft = place.name
        aliasDraft = LocationPlanner.aliasText(place.aliases)
        draftsLoaded = true
    }

    private func commitAll() {
        commitName()
        commitAliases()
    }

    private func commitName() {
        guard draftsLoaded, var place = store.place(placeID) else { return }
        let trimmed = nameDraft.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = place.name
            return
        }
        guard trimmed != place.name else { return }
        place.name = trimmed
        save(place, label: "yer adı")
    }

    private func commitAliases() {
        guard draftsLoaded, var place = store.place(placeID) else { return }
        let aliases = LocationPlanner.aliases(from: aliasDraft, excluding: place.name)
        guard aliases != place.aliases else { return }
        place.aliases = aliases
        save(place, label: "yer adları")
    }

    @discardableResult
    private func save(_ place: Place, label: String) -> Bool {
        store.upsertPlace(place)
        guard store.place(placeID) == place, store.canPersist else {
            DetailItemActions.reportNil(label, store: store, toasts: toasts)
            return false
        }
        return true
    }

    // MARK: - Actions

    private func setRadius(_ radius: Double) {
        guard var place = store.place(placeID) else { return }
        let value = LocationPlanner.clampedRadius(radius)
        guard place.radiusMeters != value else { return }
        place.radiusMeters = value
        if save(place, label: "yarıçap") {
            Haptics.selection()
        }
    }

    private func clearCoordinates() {
        guard var place = store.place(placeID), LocationPlanner.isConfigured(place) else { return }
        place.latitude = 0
        place.longitude = 0
        if save(place, label: "konumu sil") {
            toasts.show("Konum silindi")
            Haptics.medium()
        }
    }

    private func deletePlace() {
        commitAll()
        store.removePlace(placeID)
        guard store.place(placeID) == nil else {
            DetailItemActions.reportNil("yeri sil", store: store, toasts: toasts)
            return
        }
        toasts.show("Yer silindi")
        Haptics.medium()
        dismiss()
    }

    /// "Şu anki konumu kaydet": asks for permission when it was never asked (waits ≤ 60 s for the answer), then a
    /// one-shot fix (≤ 15 s). The coordinates land on the store's latest copy of the place.
    private func saveCurrentLocation() {
        guard !locating else { return }
        commitAll()
        focusedField = nil
        let service = LocationService.shared
        service.start()
        locating = true
        Task { @MainActor in
            if service.access == .notDetermined {
                service.requestWhenInUse()
                var waited = 0
                while service.access == .notDetermined && waited < 120 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    waited += 1
                }
            }
            guard service.isUsable else {
                locating = false
                toasts.show(unusableText(service.access), seconds: 7)
                Haptics.warning()
                return
            }
            let fix = await service.currentFix()
            locating = false
            guard let fix = fix, LocationPlanner.isUsableFix(latitude: fix.latitude, longitude: fix.longitude) else {
                toasts.show("Konum alınamadı. Açık alanda tekrar dene.", seconds: 6)
                Haptics.error()
                return
            }
            guard var place = store.place(placeID) else { return }
            place.latitude = fix.latitude
            place.longitude = fix.longitude
            if save(place, label: "konum kaydı") {
                toasts.show(LocationPlanner.savedText(accuracy: fix.accuracy), seconds: 6)
                Haptics.success()
            }
        }
    }

    private func unusableText(_ access: LocationAccess) -> String {
        switch access {
        case .reducedAccuracy:
            return "Kesin Konum kapalı. Ayarlar › Asist › Konum › Kesin Konum'u aç."
        case .notDetermined:
            return "Konum izni verilmedi. Tekrar dokunabilirsin."
        case .denied, .restricted:
            return "Konum izni kapalı. Ayarlar › Asist › Konum'dan “Uygulamayı Kullanırken”i seç."
        case .usable:
            return "Konum alınamadı. Tekrar dene."
        }
    }
}
