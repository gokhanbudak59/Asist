// FILE: Packages/AsistCore/Sources/AsistCore/Model/Codable+Lenient.swift
import Foundation

extension KeyedDecodingContainer {
    /// Missing, null or malformed value → `defaultValue`. Never throws.
    public func lenient<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T {
        if let value = try? decodeIfPresent(type, forKey: key) {
            return value
        }
        return defaultValue
    }

    /// Missing, null or malformed value → nil. Never throws.
    public func lenientOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        if let value = try? decodeIfPresent(type, forKey: key) {
            return value
        }
        return nil
    }
}

/// Decodes an array, silently dropping elements that fail to decode (one corrupt item never loses the rest).
public struct LossyDecodableArray<Element: Decodable>: Decodable {
    public var elements: [Element]

    public init(elements: [Element]) {
        self.elements = elements
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            // WP0-FIX: skip JSON null elements instead of stopping. decodeNil() returns true only for a null and then
            // advances the index; for a non-null value it returns false without advancing.
            let indexBefore = container.currentIndex   // WP0-FIX: progress guard (no decoder can make this spin)
            if (try? container.decodeNil()) == true {
                if container.currentIndex == indexBefore {
                    break   // WP0-FIX: a decoder that reports null without advancing cannot loop forever
                }
                continue   // WP0-FIX: null element skipped
            }
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else if (try? container.decode(SkippedElement.self)) == nil {
                break   // cannot advance: stop instead of looping forever
            }
        }
        elements = result
    }

    private struct SkippedElement: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
