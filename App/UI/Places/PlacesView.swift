// Revision 4, F6 — Ayarlar › Konumlar (07 §9.1, §9.7). Permission status card, the places (seeded once with the
// empty slots Fabrika / Ofis / Ev), "Yer ekle" and the active geofence count. Editing happens in PlaceEditorView.
// LocationService.shared is read inside body/actions only (07 §2.2 r62).
import SwiftUI
import AsistCore

/// Settings row subtitle of "Konumlar" (SettingsView).
enum PlacesSettingsText {
    /// No configured place → "Fabrika, ofis, ev · henüz kayıtlı yer yok"; else "<n> yer kayıtlı".
    static func subtitle(places: [Place]) -> String {
        LocationPlanner.settingsSubtitle(places: places)
    }
}

@MainActor
struct PlacesView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    @AppStorage("asist.places.seeded") private var seeded = false
    @State private var showAddAlert = false
    @State private var newPlaceName = ""

    /// Explicit: private @State/@AppStorage storage must not narrow the memberwise initializer (RouteDestination).
    init() {}

    var body: some View {
        let service = LocationService.shared
        let access = service.access
        let places = store.places
        let items = store.items
        List {
            statusSection(access)
            Section {
                if places.isEmpty {
                    Text("Henüz yer yok. “Yer ekle” ile başla.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .frame(minHeight: 44)
                }
                ForEach(places) { place in
                    placeRow(place, count: LocationPlanner.openItemCount(placeID: place.id, items: items))
                }
                Button {
                    newPlaceName = ""
                    showAddAlert = true
                } label: {
                    Label("Yer ekle", systemImage: "plus.circle.fill")
                        .frame(minHeight: 44)
                }
            } header: {
                SectionHeader(title: "YERLER")
            } footer: {
                Text("Bir yere gittiğinde yerin ayrıntısına gir ve “Şu anki konumu kaydet”e dokun.")
            }
            Section {
                Text(activeText(count: service.activeCount))
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("“Fabrikaya varınca …” diye söylediğinde bu yerler kullanılır. O yerdeyken kurduğun hatırlatma bir sonraki varışında çalar.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Konumlar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            LocationService.shared.start()
            seedIfNeeded()
        }
        .onChange(of: store.isLoaded) { _, loaded in
            if loaded {
                seedIfNeeded()
            }
        }
        .alert("Yer ekle", isPresented: $showAddAlert) {
            TextField("Ad, örn: Depo", text: $newPlaceName)
            Button("Vazgeç", role: .cancel) {
                newPlaceName = ""
            }
            Button("Ekle") {
                addPlace()
            }
        } message: {
            Text("Konumunu sonra, oradayken kaydedersin.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func statusSection(_ access: LocationAccess) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusSymbol(access))
                    .font(.title2)
                    .foregroundStyle(statusColor(access))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Konum izni: " + access.userText)
                        .font(.body.weight(.semibold))
                    Text(statusDetail(access))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
        switch access {
        case .notDetermined:
            Section {
                Button {
                    LocationService.shared.requestWhenInUse()
                } label: {
                    Label("Konum iznini ver", systemImage: "location.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        case .denied, .restricted, .reducedAccuracy:
            Section {
                Button {
                    PermissionCenter.openAppSettings()
                } label: {
                    Label("Ayarları Aç", systemImage: "gearshape")
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        case .usable:
            EmptyView()
        }
    }

    private func placeRow(_ place: Place, count: Int) -> some View {
        let configured = LocationPlanner.isConfigured(place)
        var detail: String = configured ? "Kayıtlı · " + LocationPlanner.radiusLabel(place.radiusMeters)
                                        : "Konum kaydedilmedi"
        if count > 0 {
            detail += " · " + String(count) + " hatırlatma"
        }
        return NavigationLink(value: Route.placeEditor(place.id)) {
            HStack(spacing: 12) {
                Image(systemName: configured ? "mappin.circle.fill" : "mappin.slash")
                    .font(.title3)
                    .foregroundStyle(configured ? Color.asistAccent : Color.orange)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name.isEmpty ? "Yer" : place.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(configured ? Color.secondary : Color.orange)
                }
            }
            .frame(minHeight: 52)
        }
    }

    // MARK: - Texts

    private func activeText(count: Int) -> String {
        let limit = String(LocationPlanner.maxRequests)
        var text = "Etkin konum hatırlatması: " + String(count) + " / " + limit + ". "
        text += "iOS aynı anda en fazla " + limit + " tanesini izlememe izin veriyor; fazlası sırayla devreye girer."
        return text
    }

    private func statusSymbol(_ access: LocationAccess) -> String {
        switch access {
        case .usable: return "location.fill"
        case .notDetermined: return "location"
        case .denied, .restricted, .reducedAccuracy: return "location.slash.fill"
        }
    }

    private func statusColor(_ access: LocationAccess) -> Color {
        switch access {
        case .usable: return Color.green
        case .notDetermined: return Color.asistAccent
        case .denied, .restricted, .reducedAccuracy: return Color.orange
        }
    }

    private func statusDetail(_ access: LocationAccess) -> String {
        switch access {
        case .usable:
            return "Yere bağlı hatırlatmalar çalışır. Konumun yalnız bu iPhone'da kalır."
        case .notDetermined:
            return "“Fabrikaya varınca hatırlat” gibi hatırlatmalar için gerekli. Yalnız uygulamayı kullanırken izni yeterli."
        case .denied:
            return "Kapalı — Ayarlar'dan aç: Ayarlar › Asist › Konum › Uygulamayı Kullanırken."
        case .restricted:
            return "Bu iPhone'da konum kullanımı kısıtlanmış (Ekran Süresi veya yönetim profili)."
        case .reducedAccuracy:
            return "Kesin Konum kapalı — yere bağlı hatırlatmalar çalışmaz. Ayarlar › Asist › Konum › Kesin Konum'u aç."
        }
    }

    // MARK: - Actions

    /// Once per install: the empty slots Fabrika / Ofis / Ev (0, 0, 150 m) when there is no place yet.
    private func seedIfNeeded() {
        guard !seeded, store.isLoaded else { return }
        if store.places.isEmpty {
            let now = Date()
            for name in LocationPlanner.seedPlaceNames {
                store.upsertPlace(Place(name: name, latitude: 0, longitude: 0,
                                        radiusMeters: LocationPlanner.defaultRadius, createdAt: now))
            }
        }
        if !store.places.isEmpty {
            seeded = true
        }
    }

    private func addPlace() {
        let name = newPlaceName.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        newPlaceName = ""
        guard !name.isEmpty else { return }
        let key = TurkishText.searchKey(name)
        if let existing = store.places.first(where: { (place: Place) -> Bool in
            place.allNames.contains { TurkishText.searchKey($0) == key }
        }) {
            toasts.show("Bu adda bir yer zaten var.")
            Haptics.warning()
            router.push(.placeEditor(existing.id))
            return
        }
        let place = Place(name: name, latitude: 0, longitude: 0, radiusMeters: LocationPlanner.defaultRadius,
                          createdAt: Date())
        store.upsertPlace(place)
        guard store.place(place.id) != nil, store.canPersist else {
            DetailItemActions.reportNil("yer ekle", store: store, toasts: toasts)
            return
        }
        Haptics.success()
        router.push(.placeEditor(place.id))
    }
}
