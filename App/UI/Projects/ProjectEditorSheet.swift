// WP10 — Proje ekle/düzenle (03 §4.9): ad, 8 renk, takma adlar (virgülle).
import SwiftUI
import AsistCore

@MainActor
struct ProjectEditorSheet: View {
    let projectID: UUID?

    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    @State private var name = ""
    @State private var color: ProjectColor = .blue
    @State private var aliasesText = ""
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private let colorColumns: [GridItem] = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    /// Explicit: private @State storage must not narrow the memberwise initializer's access (SheetHost.swift).
    init(projectID: UUID?) {
        self.projectID = projectID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Örn: Kocaeli Hattı", text: $name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .frame(minHeight: 44)
                } header: {
                    Text("Proje adı")
                } footer: {
                    if let conflict = conflictingProjectName {
                        Text("“" + conflict + "” projesi bu adı zaten kullanıyor.")
                            .foregroundStyle(Color.asistOverdue)
                    }
                }
                Section {
                    LazyVGrid(columns: colorColumns, spacing: Metrics.chipSpacing) {
                        ForEach(ProjectColor.allCases, id: \.self) { option in
                            colorSwatch(option)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Renk")
                }
                Section {
                    TextField("Örn: Kocaeli, Kocaeli hattı", text: $aliasesText, axis: .vertical)
                        .textInputAutocapitalization(.words)
                        .frame(minHeight: 44)
                    if !parsedAliases.isEmpty {
                        ChipRow {
                            ForEach(parsedAliases, id: \.self) { alias in
                                Text(alias)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.project(color).opacity(0.15), in: Capsule())
                            }
                        }
                    }
                } header: {
                    Text("Takma adlar (sesle tanıma için)")
                } footer: {
                    Text("Virgülle ayır. Söylediğin cümlede bu adlardan biri geçerse kayıt bu projeye bağlanır.")
                }
            }
            .navigationTitle(projectID == nil ? "Yeni Proje" : "Projeyi Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        router.dismissSheet()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            load()
        }
    }

    private func colorSwatch(_ option: ProjectColor) -> some View {
        Button {
            color = option
            Haptics.selection()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.project(option))
                    .frame(width: 36, height: 36)
                if option == color {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(ProjectEditorSheet.colorName(option))
        .accessibilityAddTraits(option == color ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    // MARK: - Values

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedAliases: [String] {
        ProjectEditorSheet.parseAliases(aliasesText, name: trimmedName)
    }

    /// Name of another project whose name or alias equals the entered name (folded comparison).
    private var conflictingProjectName: String? {
        let key = TurkishText.searchKey(trimmedName)
        guard !key.isEmpty else { return nil }
        for project in store.projects where project.id != projectID {
            for candidate in project.allNames where TurkishText.searchKey(candidate) == key {
                return project.name
            }
        }
        return nil
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && conflictingProjectName == nil
    }

    static func parseAliases(_ text: String, name: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n")
        var seen = Set<String>()
        let nameKey = TurkishText.searchKey(name)
        if !nameKey.isEmpty {
            seen.insert(nameKey)
        }
        var result: [String] = []
        for part in text.components(separatedBy: separators) {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TurkishText.searchKey(trimmed)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    static func colorName(_ color: ProjectColor) -> String {
        switch color {
        case .blue: return "Mavi"
        case .green: return "Yeşil"
        case .orange: return "Turuncu"
        case .red: return "Kırmızı"
        case .purple: return "Mor"
        case .teal: return "Turkuaz"
        case .pink: return "Pembe"
        case .brown: return "Kahverengi"
        }
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = projectID, let project = store.project(id) {
            name = project.name
            color = project.color
            aliasesText = project.aliases.joined(separator: ", ")
        } else {
            color = nextFreeColor()
            nameFocused = true
        }
    }

    /// First color not used by an active project (new projects get distinguishable stripes).
    private func nextFreeColor() -> ProjectColor {
        var used = Set<ProjectColor>()
        for project in store.projects where !project.archived {
            used.insert(project.color)
        }
        for option in ProjectColor.allCases where !used.contains(option) {
            return option
        }
        return .blue
    }

    private func save() {
        let finalName = trimmedName
        guard !finalName.isEmpty, conflictingProjectName == nil else { return }
        let now = Date()
        let aliases = ProjectEditorSheet.parseAliases(aliasesText, name: finalName)
        let isNew: Bool
        var project: Project
        if let id = projectID, let existing = store.project(id) {
            project = existing
            project.name = finalName
            project.color = color
            project.aliases = aliases
            project.updatedAt = now
            isNew = false
        } else {
            project = Project(name: finalName, aliases: aliases, color: color, createdAt: now)
            isNew = true
        }
        store.upsertProject(project)
        if store.canPersist {
            toasts.show(isNew ? "Proje eklendi" : "Proje kaydedildi")
            Haptics.success()
        } else {
            DetailItemActions.reportNil("proje", store: store, toasts: toasts)
        }
        router.dismissSheet()
    }
}
