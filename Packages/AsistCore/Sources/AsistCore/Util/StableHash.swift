// FILE: Packages/AsistCore/Sources/AsistCore/Util/StableHash.swift
import Foundation

public enum StableHash {
    /// FNV-1a 64-bit, lowercase hex. Stable across launches/platforms (never use hashValue/Hasher for persistence).
    public static func fnv1a64(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }
}
