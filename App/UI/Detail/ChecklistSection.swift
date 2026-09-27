// WP10 — Kontrol listesi bölümü (03 §4.8, Ek A şablonları).
import SwiftUI
import AsistCore

/// A `Section` for the detail `List`: toggle entries, add an entry, remove by swipe, append a template
/// (FAT / SAT / Devreye alma / Saha ziyareti / Toplantı hazırlığı).
@MainActor
struct ChecklistSection: View {
    let item: Item

    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.scenePhase) private var scenePhase

    @State private var newEntry = ""
    @FocusState private var addFocused: Bool

    /// Explicit: private @State/@FocusState storage must not narrow the memberwise initializer's access level.
    init(item: Item) {
        self.item = item
    }

    var body: some View {
        Section {
            ForEach(item.checklist) { entry in
                entryRow(entry)
            }
            if item.isOpen {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.asistAccent)
                        .font(.title3)
                    TextField("Madde ekle", text: $newEntry)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            addEntry(fromSubmit: true)
                        }
                        // Typed text is never dropped silently: focus loss (another field, "Bitti"), leaving the
                        // screen and backgrounding also add the pending entry, like the other detail fields.
                        .onChange(of: addFocused) { oldValue, newValue in
                            if oldValue && !newValue { addEntry(fromSubmit: false) }
                        }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .background { addEntry(fromSubmit: false) }
                        }
                        .onDisappear {
                            addEntry(fromSubmit: false)
                        }
                }
                .frame(minHeight: 44)
                Menu {
                    ForEach(ChecklistTemplates.all) { template in
                        Button(template.name) {
                            applyTemplate(template)
                        }
                    }
                } label: {
                    Label("Şablondan ekle", systemImage: Symbol.checklist)
                        .frame(minHeight: 44)
                }
            }
        } header: {
            HStack {
                SectionHeader(title: "KONTROL LİSTESİ")
                Spacer(minLength: 8)
                if !item.checklist.isEmpty {
                    Text(progressText)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }

    private var progressText: String {
        let done = item.checklist.filter { $0.done }.count
        return String(done) + "/" + String(item.checklist.count)
    }

    private func entryRow(_ entry: ChecklistEntry) -> some View {
        Button {
            toggle(entry.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.done ? Symbol.taskDone : Symbol.task)
                    .font(.title3)
                    .foregroundStyle(entry.done ? Color.asistDone : Color.secondary)
                Text(entry.text)
                    .strikethrough(entry.done)
                    .foregroundStyle(entry.done ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isOpen)
        .accessibilityValue(entry.done ? "Tamamlandı" : "Açık")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if item.isOpen {
                Button(role: .destructive) {
                    remove(entry.id)
                } label: {
                    Label("Sil", systemImage: "trash")
                }
            }
        }
    }

    private func toggle(_ entryID: UUID) {
        let result = store.update(item.id, event: nil, { edited in
            if let index = edited.checklist.firstIndex(where: { $0.id == entryID }) {
                edited.checklist[index].done.toggle()
            }
        })
        if result == nil {
            DetailItemActions.reportNil("kontrol listesi", store: store, toasts: toasts)
        } else {
            Haptics.selection()
        }
    }

    private func remove(_ entryID: UUID) {
        let result = store.update(item.id, event: nil, { edited in
            edited.checklist.removeAll(where: { $0.id == entryID })
        })
        if result == nil {
            DetailItemActions.reportNil("kontrol listesi", store: store, toasts: toasts)
        }
    }

    /// `fromSubmit`: Return was pressed — keep the keyboard for the next entry (or drop it on an empty field).
    /// Otherwise (focus loss, disappear, background) only commit the pending text and leave focus alone.
    private func addEntry(fromSubmit: Bool) {
        let text = newEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if fromSubmit { addFocused = false }
            return
        }
        let entry = ChecklistEntry(text: text)
        let result = store.update(item.id, event: nil, { edited in
            edited.checklist.append(entry)
        })
        if result == nil {
            DetailItemActions.reportNil("kontrol listesi", store: store, toasts: toasts)
            return
        }
        newEntry = ""
        if fromSubmit {
            addFocused = true      // keep the keyboard for the next entry
            Haptics.selection()
        }
    }

    private func applyTemplate(_ template: ChecklistTemplate) {
        var existing = Set<String>()
        for entry in item.checklist {
            existing.insert(TurkishText.searchKey(entry.text))
        }
        var additions: [ChecklistEntry] = []
        for entry in ChecklistTemplates.entries(for: template) {
            let key = TurkishText.searchKey(entry.text)
            if existing.contains(key) { continue }
            existing.insert(key)
            additions.append(entry)
        }
        guard !additions.isEmpty else {
            toasts.show("Bu şablonun maddeleri zaten listede.")
            return
        }
        let toAppend = additions
        guard let token = store.update(item.id, event: .edited, { edited in
            edited.checklist.append(contentsOf: toAppend)
        }) else {
            DetailItemActions.reportNil("şablon", store: store, toasts: toasts)
            return
        }
        toasts.show(template.name + " eklendi", undo: token)
        Haptics.success()
    }
}
