#if os(macOS)

import MachOKit
import TypeIndexing

/// The Core Foundation types an image defines, as swift-type-indexing's
/// `TypeDatabase` reads them: one for every `…GetTypeID` function the image
/// exports.
///
/// A CF type's Swift metadata names the type but never its module — its
/// descriptor sits in `__C` — while the framework defining it exports the
/// type's `GetTypeID` function. This attributes a private CF type such as
/// `CGSVGDocumentRef` to the image exporting `CGSVGDocumentGetTypeID`
/// (`CoreSVG`). `TypeDatabase` consults it only for names neither the SDK's
/// module interfaces nor its API notes attribute, and reads the image's
/// exports only on such a miss (evolution proposal `private-cf-type-modules`).
///
/// `TypeDatabase` keeps one source per image path, so an image whose
/// Objective-C names are registered too goes in as one
/// ``ImageDeclaredTypeNames``, which reads both; this alone is for an image
/// read for its CF types only.
///
/// ```swift
/// try await typeDatabase.index(
///     dependencies: [CFDeclaredTypeNames(machO: coreSVG, imagePath: coreSVG.imagePath)],
///     moduleFilter: { _ in false }
/// )
/// ```
public struct CFDeclaredTypeNames<MachO: MachORepresentable & Sendable>: DeclaredTypeNameSource {
    public let imagePath: String

    private let machO: MachO

    /// The only typedef names this source may give, or `nil` for every one the
    /// exports imply.
    private let admittedTypedefNames: Set<String>?

    /// - Parameters:
    ///   - machO: The image, in this process or in a file.
    ///   - imagePath: Its install path, which names the module its types are
    ///     attributed to (`…/CoreSVG.framework/Versions/A/CoreSVG` → `CoreSVG`).
    public init(machO: MachO, imagePath: String) {
        self.init(machO: machO, imagePath: imagePath, restrictedTo: nil)
    }

    /// A source giving only the names in `admittedTypedefNames` — the CF types
    /// a binary's foreign class descriptors confirm, so that an export whose
    /// name only looks like the convention (`CFGetTypeID`) or meets a typedef
    /// that is no CF class claims nothing.
    init(machO: MachO, imagePath: String, restrictedTo admittedTypedefNames: Set<String>?) {
        self.machO = machO
        self.imagePath = imagePath
        self.admittedTypedefNames = admittedTypedefNames
    }

    /// The typedef name of every CF type the image exports a `GetTypeID`
    /// function for.
    public func declaredTypeNames() async -> [String] {
        let typedefNames = machO.exportedSymbols.flatMap { exportedSymbol in
            Self.typedefNames(forExportedSymbolName: exportedSymbol.name)
        }
        guard let admittedTypedefNames else {
            return typedefNames
        }
        return typedefNames.filter { admittedTypedefNames.contains($0) }
    }

    /// The typedef names an exported symbol implies, by the CF convention that
    /// `<Name>GetTypeID` returns the type ID of `<Name>Ref`:
    /// `_CGSVGDocumentGetTypeID` → `["CGSVGDocumentRef"]`. A private function
    /// spelled with a leading underscore also names the unprefixed typedef,
    /// which is how such a type is usually declared: `__LSASNGetTypeID` →
    /// `["_LSASNRef", "LSASNRef"]`. Any other symbol — a Swift or Objective-C
    /// one, a function not ending in `GetTypeID` — implies none.
    ///
    /// A few names it gives are no type at all (`_CFGetTypeID` → `CFRef`); a
    /// lookup asks for one only by coincidence, after the SDK's attribution.
    static func typedefNames(forExportedSymbolName symbolName: String) -> [String] {
        let typeIDFunctionSuffix = "GetTypeID"
        // A C function's Mach-O symbol carries one leading underscore.
        guard symbolName.hasPrefix("_"), symbolName.hasSuffix(typeIDFunctionSuffix) else {
            return []
        }
        let functionName = symbolName.dropFirst()
        let typeNameStem = functionName.dropLast(typeIDFunctionSuffix.count)
        let unprefixedTypeNameStem = typeNameStem.drop { $0 == "_" }
        guard !unprefixedTypeNameStem.isEmpty, isCIdentifier(typeNameStem) else {
            return []
        }
        var typedefNames = [String(typeNameStem) + "Ref"]
        if unprefixedTypeNameStem.count != typeNameStem.count {
            typedefNames.append(String(unprefixedTypeNameStem) + "Ref")
        }
        return typedefNames
    }

    private static func isCIdentifier(_ candidate: Substring) -> Bool {
        guard let firstCharacter = candidate.first, !firstCharacter.isNumber else {
            return false
        }
        return candidate.allSatisfy { character in
            character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
        }
    }
}

#endif
