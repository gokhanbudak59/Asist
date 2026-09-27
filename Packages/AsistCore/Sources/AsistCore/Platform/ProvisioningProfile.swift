import Foundation

/// Uygulama paketindeki `embedded.mobileprovision` dosyasının özet bilgisi.
/// Biçim Apple'ın resmi API'si değildir (TN3125); tüm alanlar isteğe bağlı ele alınır.
public struct ProvisioningProfileInfo: Equatable, Sendable {
    public var name: String?
    public var teamName: String?
    public var teamIdentifier: String?
    public var creationDate: Date?
    public var expirationDate: Date
    public var appGroups: [String]
    public var getTaskAllow: Bool
    public var provisionsAllDevices: Bool
    public var provisionedDeviceCount: Int

    public init(name: String? = nil,
                teamName: String? = nil,
                teamIdentifier: String? = nil,
                creationDate: Date? = nil,
                expirationDate: Date,
                appGroups: [String] = [],
                getTaskAllow: Bool = false,
                provisionsAllDevices: Bool = false,
                provisionedDeviceCount: Int = 0) {
        self.name = name
        self.teamName = teamName
        self.teamIdentifier = teamIdentifier
        self.creationDate = creationDate
        self.expirationDate = expirationDate
        self.appGroups = appGroups
        self.getTaskAllow = getTaskAllow
        self.provisionsAllDevices = provisionsAllDevices
        self.provisionedDeviceCount = provisionedDeviceCount
    }

    /// Kalan süre (saniye). Negatifse süre dolmuştur.
    public func remainingSeconds(at now: Date) -> TimeInterval {
        expirationDate.timeIntervalSince(now)
    }

    public func isExpired(at now: Date) -> Bool {
        now >= expirationDate
    }

    /// Ücretsiz Apple ID profilleri 7 gün, ücretli geliştirici profilleri ~1 yıl geçerlidir.
    public var looksLikeFreeAppleID: Bool {
        guard let creationDate = creationDate else { return false }
        return expirationDate.timeIntervalSince(creationDate) <= 8 * 24 * 60 * 60
    }
}

public enum ProvisioningProfileReader {

    /// Paket içindeki profili okur. Simülatör, App Store veya imzasız kurulumda nil döner.
    public static func readEmbedded(in bundle: Bundle = .main) -> ProvisioningProfileInfo? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return parse(profileData: data)
    }

    /// CMS zarfının içindeki XML plist'i bayt aramasıyla çıkarır ve çözer.
    public static func parse(profileData data: Data) -> ProvisioningProfileInfo? {
        guard let plistData = extractPlist(from: data) else { return nil }
        guard let raw = try? PropertyListDecoder().decode(RawProfile.self, from: plistData) else {
            return nil
        }
        return ProvisioningProfileInfo(
            name: raw.name,
            teamName: raw.teamName,
            teamIdentifier: raw.teamIdentifier?.first,
            creationDate: raw.creationDate,
            expirationDate: raw.expirationDate,
            appGroups: raw.entitlements?.appGroups ?? [],
            getTaskAllow: raw.entitlements?.getTaskAllow ?? false,
            provisionsAllDevices: raw.provisionsAllDevices ?? false,
            provisionedDeviceCount: raw.provisionedDevices?.count ?? 0
        )
    }

    /// "<?xml" ile "</plist>" arasını (sonlandırıcı dahil) döndürür.
    public static func extractPlist(from data: Data) -> Data? {
        let startMarker = Data("<?xml".utf8)
        let endMarker = Data("</plist>".utf8)
        guard let start = data.range(of: startMarker) else { return nil }
        guard let end = data.range(of: endMarker, options: [], in: start.upperBound..<data.endIndex) else {
            return nil
        }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }
}

// MARK: - Ham plist modelleri (yalnız ExpirationDate zorunlu; diğerleri hatalı tipte olsa bile yok sayılır)

private struct RawProfile: Decodable {
    var name: String?
    var teamName: String?
    var teamIdentifier: [String]?
    var creationDate: Date?
    var expirationDate: Date
    var provisionsAllDevices: Bool?
    var provisionedDevices: [String]?
    var entitlements: RawEntitlements?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case teamName = "TeamName"
        case teamIdentifier = "TeamIdentifier"
        case creationDate = "CreationDate"
        case expirationDate = "ExpirationDate"
        case provisionsAllDevices = "ProvisionsAllDevices"
        case provisionedDevices = "ProvisionedDevices"
        case entitlements = "Entitlements"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expirationDate = try c.decode(Date.self, forKey: .expirationDate)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        teamName = try? c.decodeIfPresent(String.self, forKey: .teamName)
        teamIdentifier = try? c.decodeIfPresent([String].self, forKey: .teamIdentifier)
        creationDate = try? c.decodeIfPresent(Date.self, forKey: .creationDate)
        provisionsAllDevices = try? c.decodeIfPresent(Bool.self, forKey: .provisionsAllDevices)
        provisionedDevices = try? c.decodeIfPresent([String].self, forKey: .provisionedDevices)
        entitlements = try? c.decodeIfPresent(RawEntitlements.self, forKey: .entitlements)
    }
}

private struct RawEntitlements: Decodable {
    var appGroups: [String]?
    var getTaskAllow: Bool?

    enum CodingKeys: String, CodingKey {
        case appGroups = "com.apple.security.application-groups"
        case getTaskAllow = "get-task-allow"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appGroups = try? c.decodeIfPresent([String].self, forKey: .appGroups)
        getTaskAllow = try? c.decodeIfPresent(Bool.self, forKey: .getTaskAllow)
    }
}
