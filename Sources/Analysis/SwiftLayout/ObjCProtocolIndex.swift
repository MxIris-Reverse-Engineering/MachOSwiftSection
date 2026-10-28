import MachOKit
import MachOFoundation
@_spi(Core) import MachOObjCSection
@_spi(Internals) import SwiftInspection

/// Builds a per-image index of the Objective-C protocol declarations
/// (`__objc_protolist`), keyed by *Swift* qualified name, so an existential
/// component that misses the Swift protocol index can be recognized as a
/// Swift-declared `@objc` protocol.
///
/// Two sources. Every record with a legacy `_TtP` runtime name — the image's
/// own protocols and the copies Swift emits of the ones it references —
/// and the image's own protocols as `SwiftDeclaredObjCProtocolIndex` pairs
/// them with their field descriptors (evolution proposal
/// `swift-declared-objc-protocols`), which is what recognizes one the source
/// renamed with `@objc(Name)` or declared in a type. Without reflection
/// metadata the second adds nothing the first does not.
///
/// A Swift-declared `@objc` protocol emits **no** Swift protocol descriptor
/// (`__swift5_protos`) — its only runtime artifact is the Objective-C protocol
/// record, whose name is the legacy `_TtP<module><name>_` mangling (e.g.
/// `_TtP7SwiftUI36PlatformAccessibilityElementProtocol_` for
/// `SwiftUI.PlatformAccessibilityElementProtocol`). Such a protocol is always
/// class-bound and contributes no Swift witness table, so *recognizing* it is
/// all the existential layout needs — no per-protocol payload. Native
/// Objective-C protocols (plain, unmangled names like `NSCopying`) never reach
/// this index: they demangle as `__C` references and are handled structurally
/// before any lookup.
///
/// `objc.protocols64` is a concrete `MachOFile` / `MachOImage` overload (not
/// protocol-generic), so the two readers need separate builders — mirroring
/// `ObjCClassIndex`.
enum ObjCProtocolIndex {
    /// The Swift qualified names of every `@objc` protocol declared in an
    /// in-process image. An image with no `__objc_protolist` (or with only
    /// native ObjC protocols) contributes nothing.
    static func qualifiedNames(in machO: MachOImage) -> Set<String> {
        var qualifiedNames = declaredQualifiedNames(in: machO)
        for objCProtocol in machO.objc.protocols64 ?? [] {
            if let qualifiedName = swiftQualifiedName(fromLegacyProtocolMangledName: objCProtocol.mangledName(in: machO)) {
                qualifiedNames.insert(qualifiedName)
            }
        }
        return qualifiedNames
    }

    /// The Swift qualified names of every `@objc` protocol declared in a
    /// file-backed (or dyld-cache-resident) image.
    static func qualifiedNames(in machO: MachOFile) -> Set<String> {
        var qualifiedNames = declaredQualifiedNames(in: machO)
        for objCProtocol in machO.objc.protocols64 ?? [] {
            if let qualifiedName = swiftQualifiedName(fromLegacyProtocolMangledName: objCProtocol.mangledName(in: machO)) {
                qualifiedNames.insert(qualifiedName)
            }
        }
        return qualifiedNames
    }

    /// The image's own `@objc` protocols declared in Swift, renamed and
    /// nested ones included.
    private static func declaredQualifiedNames(in machO: some MachORepresentableWithCache) -> Set<String> {
        Set(SwiftDeclaredObjCProtocolIndex.shared.protocols(in: machO).map(\.qualifiedName))
    }

    /// Parses the legacy `_TtP<length>module<length>name_` protocol mangling
    /// into `"module.name"`, or `nil` for any other name form (a native ObjC
    /// protocol's plain name, a Punycode-encoded Unicode identifier, a custom
    /// `@objc(Name)` runtime name — none of which can be matched back to a
    /// Swift qualified name here, so they are skipped rather than misindexed).
    static func swiftQualifiedName(fromLegacyProtocolMangledName mangledName: String) -> String? {
        guard mangledName.hasPrefix("_TtP"), mangledName.hasSuffix("_") else { return nil }
        var remainder = mangledName.dropFirst(4).dropLast(1)
        var components: [String] = []
        while !remainder.isEmpty {
            let digits = remainder.prefix(while: { $0.isASCII && $0.isWholeNumber })
            guard let length = Int(digits), length > 0 else { return nil }
            remainder = remainder.dropFirst(digits.count)
            guard remainder.count >= length else { return nil }
            components.append(String(remainder.prefix(length)))
            remainder = remainder.dropFirst(length)
        }
        guard components.count == 2 else { return nil }
        return components.joined(separator: ".")
    }
}
