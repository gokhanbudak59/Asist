// Revision 4 (07 §5.10): "Kilit ekranı ve widget'lar" — how to put the "Asist Dinle" control on the Lock Screen
// and in Control Center (iOS 18), and the home / lock screen widgets. Reached from Ayarlar › Tetikleyiciler and
// Ayarlar › İmza ve izinler.
import SwiftUI
import AsistCore

struct WidgetGuideView: View {
    struct StepGroup {
        let title: String
        let systemImage: String
        let steps: [String]
        let note: String?
    }

    init() {}

    var body: some View {
        let available = WidgetSnapshotWriter.shared.isAvailable
        let statusValue: String = available ? "Açık" : "Kapalı"
        List {
            Section {
                Text("Uygulama kapalıyken Asist'e en hızlı yol: kilit ekranının altındaki **Asist Dinle** düğmesi. Tek dokunuş, Face ID, Asist açılır ve dinler.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if !WidgetGuideView.supportsControls {
                    Label("Kilit ekranı ve Denetim Merkezi düğmeleri iOS 18 ister. Bu telefonda yalnız widget'lar kullanılabilir.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.orange)
                }
            }

            ForEach(WidgetGuideView.groups.indices, id: \.self) { groupIndex in
                groupSection(WidgetGuideView.groups[groupIndex])
            }

            Section {
                HStack {
                    Text("Widget veri paylaşımı")
                    Spacer()
                    Text(statusValue)
                        .foregroundStyle(available ? Color.asistDone : Color.orange)
                }
            } header: {
                Text("Durum")
            } footer: {
                Text(WidgetGuideView.statusText(available: available))
            }

            Section {
                EmptyView()
            } footer: {
                Text(WidgetGuideView.volumeKeyNote)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Kilit ekranı ve widget'lar")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Rows

    @ViewBuilder
    private func groupSection(_ group: StepGroup) -> some View {
        Section {
            ForEach(group.steps.indices, id: \.self) { index in
                stepRow(number: index + 1, text: group.steps[index])
            }
            if let note = group.note {
                Label {
                    Text(WidgetGuideView.rich(note))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.asistDone)
                }
            }
        } header: {
            Label(group.title, systemImage: group.systemImage)
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.asistAccent)
                    .frame(width: 32, height: 32)
                Text(String(number))
                    .font(.headline)
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)
            Text(WidgetGuideView.rich(text))
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Adım \(number). ") + Text(WidgetGuideView.rich(text)))
    }

    // MARK: Content

    static let groups: [StepGroup] = [
        StepGroup(
            title: "Kilit ekranına “Asist Dinle” düğmesi",
            systemImage: "lock.iphone",
            steps: [
                "Kilit ekranında ekrana basılı tut → **Özelleştir** → **Kilit Ekranı**.",
                "Alttaki fener ya da kamera düğmesinin **−** işaretine dokun, sonra boş kalan yerdeki **+** → **Asist** → **Asist Dinle**.",
                "Sağ üstten **Bitti**'ye dokun."
            ],
            note: "Artık kilit ekranından tek dokunuşla Asist açılır ve dinler (önce Face ID ister)."),
        StepGroup(
            title: "Denetim Merkezi",
            systemImage: "switch.2",
            steps: [
                "Ekranın sağ üst köşesinden aşağı kaydır.",
                "Sol üstteki **+** → **Denetim Ekle**.",
                "**Asist**'i ara → **Asist Dinle** ya da **Asist Yaz**."
            ],
            note: nil),
        StepGroup(
            title: "Ana ekran widget'ı",
            systemImage: "apps.iphone",
            steps: [
                "Ana ekranda boş bir yere basılı tut → **Düzenle** → **Widget Ekle**.",
                "**Asist**'i seç → **Küçük** ya da **Orta** boyutu ekle."
            ],
            note: "Geciken, bugün ve takip sayılarını gösterir. Küçüğe dokununca Asist dinler; ortada **Dinle** ve **Yaz** düğmeleri ile sıradaki üç iş var."),
        StepGroup(
            title: "Kilit ekranı widget'ları",
            systemImage: "clock",
            steps: [
                "Kilit ekranında basılı tut → **Özelleştir** → **Kilit Ekranı**.",
                "Saatin altındaki alana dokun → **Asist** → **Asist Dinle** (yuvarlak) ya da **Sıradaki iş**."
            ],
            note: nil)
    ]

    static let volumeKeyNote = "Ses kısma tuşu yalnız Asist açıkken çalışır; iOS buna başka türlü izin vermez. Uygulama kapalıyken kilit ekranı düğmesini ya da Arkaya Dokunma'yı kullan."

    static func statusText(available: Bool) -> String {
        if available {
            return "Açık — widget'lar geciken ve bugünkü işlerini gösterir. Bir kayıt değişince birkaç saniye içinde güncellenir."
        }
        return "Kapalı — widget'lar içerik göstermez, yalnız Asist'i açar. Düğmeler her durumda çalışır."
    }

    /// true on iOS 18+ (Control Center / Lock Screen controls).
    static var supportsControls: Bool {
        if #available(iOS 18.0, *) {
            return true
        }
        return false
    }

    static func rich(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let value = try? AttributedString(markdown: markdown, options: options) {
            return value
        }
        return AttributedString(markdown)
    }
}
