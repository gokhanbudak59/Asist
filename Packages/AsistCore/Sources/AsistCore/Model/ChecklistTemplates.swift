// API: Packages/AsistCore/Sources/AsistCore/Model/ChecklistTemplates.swift
// WP2 (04 §3.5.6). Template texts are 03 Ek A verbatim (FAT, SAT, Devreye alma, Saha ziyareti, Toplantı hazırlığı).
import Foundation

public struct ChecklistTemplate: Equatable, Identifiable {
    public var id: String           // "fat", "sat", "devreye_alma", "saha_ziyareti", "toplanti"
    public var name: String         // "FAT (Fabrika Kabul Testi)", …
    public var entries: [String]    // exact texts from 03 Ek A

    public init(id: String, name: String, entries: [String]) {
        self.id = id
        self.name = name
        self.entries = entries
    }
}

public enum ChecklistTemplates {
    public static let all: [ChecklistTemplate] = [fat, sat, devreyeAlma, sahaZiyareti, toplanti]

    /// Fresh entries (new UUIDs, done = false) for appending to an item's checklist.
    public static func entries(for template: ChecklistTemplate) -> [ChecklistEntry] {
        template.entries.map { ChecklistEntry(text: $0) }
    }

    /// Template by id ("fat", "sat", "devreye_alma", "saha_ziyareti", "toplanti"); nil when unknown.
    public static func template(id: String) -> ChecklistTemplate? {
        all.first(where: { $0.id == id })
    }

    // Separate constants keep each array literal small for the type checker.

    private static let fat = ChecklistTemplate(id: "fat", name: "FAT (Fabrika Kabul Testi)", entries: [
        "Test prosedürü müşteriye gönderildi ve onaylandı",
        "Katılımcılar ve tarih teyit edildi",
        "I/O listesi ve test kayıt formları hazır",
        "PLC/HMI/robot program yedekleri alındı (sürüm etiketli)",
        "Safety fonksiyon testleri planlandı",
        "Eksik listesi (punch list) şablonu hazır",
        "Test sonrası tutanak imzalandı"
    ])

    private static let sat = ChecklistTemplate(id: "sat", name: "SAT (Saha Kabul Testi)", entries: [
        "Saha hazırlığı (enerji, hava, montaj) teyit edildi",
        "FAT eksikleri kapatıldı",
        "Test prosedürü ve formlar sahada",
        "Müşteri operatörleri test için hazır",
        "Performans/çevrim süresi ölçümleri yapıldı",
        "Eksik listesi ve kabul tutanağı imzalandı"
    ])

    private static let devreyeAlma = ChecklistTemplate(id: "devreye_alma", name: "Devreye alma", entries: [
        "Enerji öncesi pano ve kablaj kontrolleri",
        "I/O kontrolü (giriş/çıkış tek tek)",
        "Safety devreye alma ve doğrulama",
        "Sürücü/servo parametre yedekleri",
        "Proses ayarları ve deneme üretimi",
        "Operatör ve bakım eğitimi",
        "Son program yedekleri ve doküman teslimi"
    ])

    private static let sahaZiyareti = ChecklistTemplate(id: "saha_ziyareti", name: "Saha ziyareti", entries: [
        "Laptop, şarj aleti, programlama kabloları (Ethernet, USB, seri)",
        "Yazılım lisansları erişilebilir",
        "İSG ekipmanı (baret, iş ayakkabısı, gözlük)",
        "Son proje yedeği yanında",
        "Ziyaret notları ve fotoğraflar kaydedildi",
        "Açık konular Takip olarak eklendi"
    ])

    private static let toplanti = ChecklistTemplate(id: "toplanti", name: "Toplantı hazırlığı", entries: [
        "Gündem gönderildi",
        "Önceki toplantının aksiyonları gözden geçirildi",
        "Gerekli dokümanlar hazır",
        "Toplantı sonrası aksiyonlar Asist'e kaydedildi"
    ])
}
