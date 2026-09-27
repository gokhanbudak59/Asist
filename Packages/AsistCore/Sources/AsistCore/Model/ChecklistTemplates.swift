// API: Packages/AsistCore/Sources/AsistCore/Model/ChecklistTemplates.swift
// WP0 STUB (04 §3.5.6) — WP2 owns this file. Template texts are 03 Ek A verbatim.
import Foundation

public struct ChecklistTemplate: Equatable, Identifiable {
    public var id: String           // "fat", "sat", "devreye_alma", "saha_ziyareti", "toplanti"
    public var name: String         // "FAT (Fabrika Kabul Testi)", …
    public var entries: [String]    // exact texts from 03 Ek A
}

public enum ChecklistTemplates {
    public static let all: [ChecklistTemplate] = [
        ChecklistTemplate(id: "fat", name: "FAT (Fabrika Kabul Testi)", entries: [
            "Test prosedürü müşteriye gönderildi ve onaylandı",
            "Katılımcılar ve tarih teyit edildi",
            "I/O listesi ve test kayıt formları hazır",
            "PLC/HMI/robot program yedekleri alındı (sürüm etiketli)",
            "Safety fonksiyon testleri planlandı",
            "Eksik listesi (punch list) şablonu hazır",
            "Test sonrası tutanak imzalandı"
        ]),
        ChecklistTemplate(id: "sat", name: "SAT (Saha Kabul Testi)", entries: [
            "Saha hazırlığı (enerji, hava, montaj) teyit edildi",
            "FAT eksikleri kapatıldı",
            "Test prosedürü ve formlar sahada",
            "Müşteri operatörleri test için hazır",
            "Performans/çevrim süresi ölçümleri yapıldı",
            "Eksik listesi ve kabul tutanağı imzalandı"
        ]),
        ChecklistTemplate(id: "devreye_alma", name: "Devreye alma", entries: [
            "Enerji öncesi pano ve kablaj kontrolleri",
            "I/O kontrolü (giriş/çıkış tek tek)",
            "Safety devreye alma ve doğrulama",
            "Sürücü/servo parametre yedekleri",
            "Proses ayarları ve deneme üretimi",
            "Operatör ve bakım eğitimi",
            "Son program yedekleri ve doküman teslimi"
        ]),
        ChecklistTemplate(id: "saha_ziyareti", name: "Saha ziyareti", entries: [
            "Laptop, şarj aleti, programlama kabloları (Ethernet, USB, seri)",
            "Yazılım lisansları erişilebilir",
            "İSG ekipmanı (baret, iş ayakkabısı, gözlük)",
            "Son proje yedeği yanında",
            "Ziyaret notları ve fotoğraflar kaydedildi",
            "Açık konular Takip olarak eklendi"
        ]),
        ChecklistTemplate(id: "toplanti", name: "Toplantı hazırlığı", entries: [
            "Gündem gönderildi",
            "Önceki toplantının aksiyonları gözden geçirildi",
            "Gerekli dokümanlar hazır",
            "Toplantı sonrası aksiyonlar Asist'e kaydedildi"
        ])
    ]

    public static func entries(for template: ChecklistTemplate) -> [ChecklistEntry] {
        template.entries.map { ChecklistEntry(text: $0) }
    }
}
