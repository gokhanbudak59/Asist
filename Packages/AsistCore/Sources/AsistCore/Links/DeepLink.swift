// FILE: Packages/AsistCore/Sources/AsistCore/Links/DeepLink.swift
import Foundation

/// Target of `asist://sekme/<kod>`: switches to that tab's root (Shortcuts "URL Aç", CI simulator screenshots).
/// Codes are ASCII lowercase so they need no percent-encoding.
public enum DeepLinkTab: String, CaseIterable, Equatable {
    case today = "bugun"
    case lists = "listeler"
    case projects = "projeler"
    case settings = "ayarlar"
}

/// Target of `asist://ekran/<kod>` (revision 4, 07 R4-D9): opens a screen on its tab. ASCII lowercase codes.
public enum DeepLinkScreen: String, CaseIterable, Equatable {
    case weeklyReport = "haftalik-rapor"
    case people = "kisiler"
    case places = "konumlar"
    case updates = "guncelleme"
    case calendar = "takvim"
}

public enum DeepLink: Equatable {
    case listen(kind: ItemKind?, projectID: UUID?)   // asist://dinle?tur=hatirlatma|gorev|not|takip&proje=<uuid>
    case compose                                     // asist://yaz
    case today                                       // asist://bugun
    case item(UUID)                                  // asist://kayit/<uuid>
    case completeItem(UUID)                          // asist://kayit/<uuid>?eylem=yaptim
    case editItem(UUID)                              // asist://kayit/<uuid>?eylem=duzenle
    case endOfDay                                    // asist://gunsonu
    case readAgenda                                  // asist://oku
    case settingsTriggers                            // asist://ayarlar/tetikleyiciler
    case tab(DeepLinkTab)                            // asist://sekme/bugun|listeler|projeler|ayarlar
    case screen(DeepLinkScreen)                      // asist://ekran/haftalik-rapor|kisiler|konumlar|guncelleme|takvim

    public static let scheme = "asist"

    public var url: URL {
        var c = URLComponents()
        c.scheme = DeepLink.scheme
        switch self {
        case .listen(let kind, let projectID):
            c.host = "dinle"
            var query: [URLQueryItem] = []
            if let kind = kind { query.append(URLQueryItem(name: "tur", value: DeepLink.kindCode(kind))) }
            if let projectID = projectID { query.append(URLQueryItem(name: "proje", value: projectID.uuidString)) }
            if !query.isEmpty { c.queryItems = query }
        case .compose:
            c.host = "yaz"
        case .today:
            c.host = "bugun"
        case .item(let id):
            c.host = "kayit"
            c.path = "/" + id.uuidString
        case .completeItem(let id):
            c.host = "kayit"
            c.path = "/" + id.uuidString
            c.queryItems = [URLQueryItem(name: "eylem", value: "yaptim")]
        case .editItem(let id):
            c.host = "kayit"
            c.path = "/" + id.uuidString
            c.queryItems = [URLQueryItem(name: "eylem", value: "duzenle")]
        case .endOfDay:
            c.host = "gunsonu"
        case .readAgenda:
            c.host = "oku"
        case .settingsTriggers:
            c.host = "ayarlar"
            c.path = "/tetikleyiciler"
        case .tab(let tab):
            c.host = "sekme"
            c.path = "/" + tab.rawValue
        case .screen(let screen):
            c.host = "ekran"
            c.path = "/" + screen.rawValue
        }
        return c.url ?? URL(string: "asist://bugun")!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == DeepLink.scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased() else { return nil }
        let items = comps.queryItems ?? []
        func query(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        let pathParts = comps.path.split(separator: "/").map(String.init)
        switch host {
        case "dinle":
            let kind = query("tur").flatMap(DeepLink.kind(fromCode:))
            let project = query("proje").flatMap { UUID(uuidString: $0) }
            self = .listen(kind: kind, projectID: project)
        case "yaz":
            self = .compose
        case "bugun":
            self = .today
        case "kayit":
            guard let first = pathParts.first, let id = UUID(uuidString: first) else { return nil }
            switch query("eylem") ?? "" {
            case "yaptim": self = .completeItem(id)
            case "duzenle": self = .editItem(id)
            default: self = .item(id)
            }
        case "gunsonu":
            self = .endOfDay
        case "oku":
            self = .readAgenda
        case "ayarlar":
            self = .settingsTriggers
        case "sekme":
            guard let first = pathParts.first, let tab = DeepLinkTab(rawValue: first.lowercased()) else { return nil }
            self = .tab(tab)
        case "ekran":
            guard let first = pathParts.first, let screen = DeepLinkScreen(rawValue: first.lowercased()) else { return nil }
            self = .screen(screen)
        default:
            return nil
        }
    }

    public static func kindCode(_ kind: ItemKind) -> String {
        switch kind {
        case .reminder: return "hatirlatma"
        case .task: return "gorev"
        case .note: return "not"
        case .waiting: return "takip"
        }
    }

    public static func kind(fromCode code: String) -> ItemKind? {
        switch code.lowercased() {
        case "hatirlatma": return .reminder
        case "gorev": return .task
        case "not": return .note
        case "takip": return .waiting
        default: return nil
        }
    }
}
