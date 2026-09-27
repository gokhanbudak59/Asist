// WP11 — Veriler: dışa aktar, güvenli (security-scoped) içe aktar, günlük yedekler, Son silinenler
// (03 §4.11 "Veri", 04 §5.2 exact import pattern, §9 r35/r43; 05a #12/#24).
import SwiftUI
import UniformTypeIdentifiers
import AsistCore

struct DataSettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var backups: [BackupFile] = []
    @State private var restoreCandidate: BackupFile?
    @State private var showRestoreConfirm = false

    struct BackupFile: Identifiable, Equatable {
        let url: URL
        /// "yyyy-MM-dd" part of "asist-yedek-yyyy-MM-dd.json".
        let dayText: String
        var id: String { url.lastPathComponent }
    }

    var body: some View {
        List {
            Section {
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Dışa aktar (JSON)", systemImage: Symbol.export)
                    }
                } else {
                    Button {
                        prepareExport()
                    } label: {
                        Label(store.isLoaded ? "Dışa aktarmayı hazırla" : "Veriler henüz okunamadı",
                              systemImage: Symbol.export)
                    }
                    .disabled(!store.isLoaded)
                }
                Button {
                    showImporter = true
                } label: {
                    Label("İçe aktar…", systemImage: Symbol.importData)
                }
                .disabled(!store.isLoaded)
            } header: {
                Text("Yedek dosyası")
            } footer: {
                Text("Dışa aktardığın dosyayı bilgisayarına, e-postana veya iCloud Drive'a kaydet. İçe aktarırken önce kaç kayıt geleceğini gösteririm: “Birleştir” mevcut kayıtları korur, “Değiştir” kayıtları ve ayarları yedektekiyle değiştirir.")
            }

            Section {
                if backups.isEmpty {
                    Text("Henüz günlük yedek yok. İlk yedek, bugün ilk kayıttan sonra alınır.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                } else {
                    ForEach(backups) { backup in
                        Button {
                            restoreCandidate = backup
                            showRestoreConfirm = true
                        } label: {
                            HStack {
                                Label(DataSettingsView.backupTitle(backup), systemImage: "clock.arrow.circlepath")
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Text("Geri yükle")
                                    .font(.footnote)
                                    .foregroundStyle(Color.asistAccent)
                            }
                        }
                    }
                }
            } header: {
                Text("Otomatik yedekler")
            } footer: {
                Text("Her gün bir yedek alırım (son 7 gün kalır); içe aktarmadan önce de bir kopya alırım. Yedekler ve okunabilir açık işler listesi (Asist-acik-isler.txt) Dosyalar › Bu iPhone'da › Asist › Yedekler klasöründedir. Asist'i silersen bu klasör de silinir; haftada bir bilgisayarına veya iCloud Drive'a kopyala.")
            }

            Section {
                NavigationLink(value: Route.recentlyDeleted) {
                    HStack {
                        Label("Son silinenler", systemImage: "trash")
                        Spacer()
                        let count = store.recentlyDeleted.count
                        if count > 0 {
                            Text(String(count))
                                .foregroundStyle(Color.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } footer: {
                Text("Silinen kayıtlar 30 gün boyunca buradan geri getirilebilir.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Veriler")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Bu yedeğe dönülsün mü?", isPresented: $showRestoreConfirm, presenting: restoreCandidate) { backup in
            Button("Geri yükle", role: .destructive) {
                restore(backup)
            }
            Button("Vazgeç", role: .cancel) {
                restoreCandidate = nil
            }
        } message: { backup in
            Text(DataSettingsView.restoreMessage(backup))
        }
        .dataImportFlow(isPresented: $showImporter) { message in
            toasts.show(message)
        }
        .onAppear {
            prepareExport()
            loadBackups()
        }
        .onChange(of: store.data) { _, _ in
            prepareExport()
        }
    }

    // MARK: Export

    /// Writes the export to a temporary file "Asist-yedek-yyyy-MM-dd-HHmm.json" for ShareLink.
    private func prepareExport() {
        guard store.isLoaded else {
            exportURL = nil
            return
        }
        let data = store.exportData()
        guard !data.isEmpty else {
            exportURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(DataSettingsView.exportFileName(now: Date(), calendar: AppTime.calendar))
        do {
            try data.write(to: url, options: [.atomic])
            exportURL = url
        } catch {
            AsistLog.error("Dışa aktarma dosyası yazılamadı: " + error.localizedDescription, .store)
            exportURL = nil
        }
    }

    static func exportFileName(now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let day = AsistCalendar.pad(c.year ?? 0, 4) + "-" + AsistCalendar.pad(c.month ?? 1, 2) + "-" + AsistCalendar.pad(c.day ?? 1, 2)
        let time = AsistCalendar.pad(c.hour ?? 0, 2) + AsistCalendar.pad(c.minute ?? 0, 2)
        return "Asist-yedek-" + day + "-" + time + ".json"
    }

    // MARK: Daily backups

    private func loadBackups() {
        let directory = store.files.backupDirectory
        let prefix = "asist-yedek-"
        let suffix = ".json"
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory,
                                                                   includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])
            var found: [BackupFile] = []
            for url in urls {
                let name = url.lastPathComponent
                guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count > prefix.count + suffix.count else { continue }
                let middle = String(name.dropFirst(prefix.count).dropLast(suffix.count))
                found.append(BackupFile(url: url, dayText: middle))
            }
            backups = found.sorted { $0.dayText > $1.dayText }
        } catch {
            backups = []
            AsistLog.info("Yedek klasörü listelenemedi: " + error.localizedDescription, .store)
        }
    }

    /// "2026-09-27" → "27 Eylül 2026"; the safety copy written before an import
    /// ("2026-09-27-101500-ice-aktarma-oncesi") → "27 Eylül 2026 10:15 · içe aktarma öncesi"; anything else unchanged.
    static func backupTitle(_ backup: BackupFile) -> String {
        let parts = backup.dayText.split(separator: "-")
        guard parts.count >= 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return backup.dayText
        }
        let date = String(day) + " " + SettingsFormat.monthName(month) + " " + String(year)
        if parts.count == 3 {
            return date
        }
        let time = Array(parts[3])
        var suffix = ""
        if time.count >= 4, time.allSatisfy({ $0.isNumber }) {
            suffix = " " + String(time[0..<2]) + ":" + String(time[2..<4])
        }
        if backup.dayText.hasSuffix("ice-aktarma-oncesi") {
            suffix += " · içe aktarma öncesi"
        }
        return date + suffix
    }

    static func restoreMessage(_ backup: BackupFile) -> String {
        "Şu anki kayıtlar ve ayarlar " + backupTitle(backup)
            + " tarihli yedekle değiştirilir. Değiştirmeden önce mevcut verinin bir kopyası Yedekler klasörüne alınır."
    }

    /// Restore from a daily backup = import with mode .replace (the store first writes today's backup copy, §9 r43).
    private func restore(_ backup: BackupFile) {
        restoreCandidate = nil
        guard let data = try? Data(contentsOf: backup.url) else {
            toasts.show("Yedek dosyası okunamadı.")
            Haptics.error()
            return
        }
        guard store.importPreview(data) != nil else {
            toasts.show("Bu yedek okunamadı; verilerin değişmedi.")
            Haptics.error()
            return
        }
        if store.importData(data, mode: .replace) {
            AsistLog.info("Günlük yedekten geri yüklendi: " + backup.dayText, .store)
            toasts.show("Yedekten geri yüklendi.")
            Haptics.success()
            Task { @MainActor in
                await AppEnvironment.shared.engine.rebuildAll(reason: "restoreBackup")
            }
            loadBackups()
        } else {
            toasts.show("Geri yüklenemedi; verilerin değişmedi.")
            Haptics.error()
        }
    }
}

// MARK: - Import flow (shared with OnboardingView's "Yedekten geri yükle", 03 §9 r25)

/// Security-scoped `.fileImporter` → preview alert "n kayıt, m proje içe aktarılacak" → Birleştir / Değiştir.
/// `onMessage` receives the Turkish result line (DataSettingsView shows a toast; onboarding shows it inline
/// because the toast host is covered by the full-screen cover).
struct DataImportFlow: ViewModifier {
    @Binding var isPresented: Bool
    let onMessage: (String) -> Void

    @Environment(DataStore.self) private var store
    @State private var pendingImportData: Data?
    @State private var preview: ImportPreview?
    @State private var showConfirm = false

    /// Explicit: private @State/@Environment storage must not narrow the memberwise initializer's access
    /// (`View.dataImportFlow` below is outside this type's private scope).
    init(isPresented: Binding<Bool>, onMessage: @escaping (String) -> Void) {
        self._isPresented = isPresented
        self.onMessage = onMessage
    }

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [UTType.json]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    onMessage("Dosya okunamadı.")
                    return
                }
                pendingImportData = data           // preview + merge/replace operate on the in-memory Data
                prepare(data)
            }
            .alert("İçe aktarılsın mı?", isPresented: $showConfirm, presenting: preview) { _ in
                Button("Birleştir") {
                    apply(.merge)
                }
                Button("Değiştir", role: .destructive) {
                    apply(.replace)
                }
                Button("Vazgeç", role: .cancel) {
                    pendingImportData = nil
                    preview = nil
                }
            } message: { value in
                Text(DataImportFlow.summary(value))
            }
    }

    private func prepare(_ data: Data) {
        guard store.isLoaded else {
            pendingImportData = nil
            onMessage("Veriler henüz okunamadı; telefonun kilidini açıp tekrar dene.")
            return
        }
        guard let value = store.importPreview(data) else {
            pendingImportData = nil
            onMessage("Bu dosya bir Asist yedeği değil ya da bozuk. Verilerin değişmedi.")
            return
        }
        preview = value
        Task { @MainActor in
            // Let the document picker finish dismissing before the alert is presented.
            try? await Task.sleep(nanoseconds: 400_000_000)
            showConfirm = true
        }
    }

    private func apply(_ mode: ImportMode) {
        guard let data = pendingImportData else { return }
        let count = preview?.itemCount ?? 0
        let modeName: String = mode == .merge ? "merge" : "replace"
        pendingImportData = nil
        preview = nil
        if store.importData(data, mode: mode) {
            AsistLog.info("İçe aktarma tamam: " + String(count) + " kayıt, mod " + modeName, .store)
            Haptics.success()
            if mode == .merge {
                onMessage("İçe aktarıldı: " + String(count) + " kayıt birleştirildi.")
            } else {
                onMessage("İçe aktarıldı: veriler yedektekiyle değiştirildi.")
            }
            Task { @MainActor in
                await AppEnvironment.shared.engine.rebuildAll(reason: "import")
            }
        } else {
            AsistLog.error("İçe aktarma başarısız (mod " + modeName + ")", .store)
            Haptics.error()
            onMessage("İçe aktarılamadı. Verilerin değişmedi.")
        }
    }

    static func summary(_ value: ImportPreview) -> String {
        let head = String(value.itemCount) + " kayıt, " + String(value.projectCount) + " proje içe aktarılacak."
        let merge = " Birleştir: mevcut kayıtların korunur, aynı kayıtta yenisi kalır."
        let replace = " Değiştir: kayıtlar ve ayarlar yedektekiyle değiştirilir; önce mevcut verinin kopyası Yedekler klasörüne alınır."
        return head + merge + replace
    }
}

extension View {
    /// See `DataImportFlow`. Main-actor: it constructs the (main-actor) modifier; callers are View bodies.
    @MainActor
    func dataImportFlow(isPresented: Binding<Bool>, onMessage: @escaping (String) -> Void) -> some View {
        modifier(DataImportFlow(isPresented: isPresented, onMessage: onMessage))
    }
}
