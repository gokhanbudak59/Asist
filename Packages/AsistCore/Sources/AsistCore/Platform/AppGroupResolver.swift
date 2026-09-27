import Foundation

public struct ResolvedAppGroup: Equatable, Sendable {
    public let identifier: String
    public let containerURL: URL

    public init(identifier: String, containerURL: URL) {
        self.identifier = identifier
        self.containerURL = containerURL
    }
}

/// İmzalayıcıların yeniden adlandırdığı App Group kimliklerini de dener
/// (ör. AltStore: "group.com.gokhanbudak.asist.<TEAMID>", Info.plist "ALTAppGroups").
public enum AppGroupResolver {

    public static func candidates(expected: String,
                                  infoPlistGroups: [String],
                                  profileGroups: [String]) -> [String] {
        let base = expected.hasPrefix("group.") ? String(expected.dropFirst(6)) : expected
        let related = (infoPlistGroups + profileGroups).filter { $0.contains(base) }
        var result: [String] = []
        for identifier in [expected] + related where !identifier.isEmpty && !result.contains(identifier) {
            result.append(identifier)
        }
        return result
    }

    /// `containerURL` iOS'ta entitlement yoksa nil döner; ilk nil olmayan aday seçilir.
    public static func resolve(expected: String,
                               infoPlistGroups: [String],
                               profileGroups: [String],
                               containerURL: (String) -> URL?) -> ResolvedAppGroup? {
        for identifier in candidates(expected: expected,
                                     infoPlistGroups: infoPlistGroups,
                                     profileGroups: profileGroups) {
            if let url = containerURL(identifier) {
                return ResolvedAppGroup(identifier: identifier, containerURL: url)
            }
        }
        return nil
    }
}

#if canImport(Darwin)
public enum SharedContainerLocator {
    public static let expectedAppGroup = "group.com.gokhanbudak.asist"

    /// Uygulama ve widget uzantısında aynı şekilde çağrılır (Bundle.main her birinin kendi paketi).
    public static func resolve(bundle: Bundle = .main,
                               fileManager: FileManager = .default) -> ResolvedAppGroup? {
        let infoGroups = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        let profileGroups = ProvisioningProfileReader.readEmbedded(in: bundle)?.appGroups ?? []
        return AppGroupResolver.resolve(expected: expectedAppGroup,
                                        infoPlistGroups: infoGroups,
                                        profileGroups: profileGroups) { identifier in
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }
    }
}
#endif
