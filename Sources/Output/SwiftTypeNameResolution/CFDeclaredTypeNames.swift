#if os(macOS)

import MachOKit
import TypeIndexing

/// The Core Foundation types an image defines, as swift-type-indexing's
/// `TypeDatabase` reads them: one for every `…GetTypeID` function the image
/// exports.
///
/// A CF type's Swift metadata names the type but never its module — its
/// descriptor sits in `__C` — while the framework defining it exports the
/// type's `GetTypeID` function. Registered beside `ObjCDeclaredTypeNames`, this
/// attributes a private CF type such as `CGSVGDocumentRef` to the image
/// exporting `CGSVGDocumentGetTypeID` (`CoreSVG`). `TypeDatabase` consults it
/// only for names neither the SDK's module interfaces nor its API notes
/// attribute, and reads the image's exports only on such a miss (evolution
/// proposal `private-cf-type-modules`).
///
/// ```swift
/// let sources: [any DeclaredTypeNameSource] = dependencyImages.flatMap { image in
///     [
///         ObjCDeclaredTypeNames(machO: image, imagePath: image.imagePath),
///         CFDeclaredTypeNames(machO: image, imagePath: image.imagePath),
///     ]
/// }
/// ```
public struct CFDeclaredTypeNames<MachO: MachORepresentable & Sendable>: DeclaredTypeNameSource {
    public let imagePath: String

    private let machO: MachO

    /// - Parameters:
    ///   - machO: The image, in this process or in a file.
    ///   - imagePath: Its install path, which names the module its types are
    ///     attributed to (`…/CoreSVG.framework/Versions/A/CoreSVG` → `CoreSVG`).
    public init(machO: MachO, imagePath: String) {
        self.machO = machO
        self.imagePath = imagePath
    }

    /// The typedef name of every CF type the image exports a `GetTypeID`
    /// function for.
    public func declaredTypeNames() async -> [String] {
        machO.exportedSymbols.flatMap { exportedSymbol in
            Self.typedefNames(forExportedSymbolName: exportedSymbol.name)
        }
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
