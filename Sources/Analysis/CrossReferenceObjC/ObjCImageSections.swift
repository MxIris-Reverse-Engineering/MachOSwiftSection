import Foundation
import MachOKit
import CrossReferenceCore

/// The Objective-C sections of one image a scan reads: its own selector
/// stubs, its selector, class and superclass references. Kept on the image's
/// function table, made when the first scan of the image asks.
///
/// Selector names are kept as pointers into the image's memory — the
/// cache's selector strings — which stay valid for the life of the
/// analyzer's memory; that is what makes the unchecked `Sendable` sound.
package final class ObjCImageSections: ImageFunctionTableAttachment, @unchecked Sendable {
    /// `__objc_stubs`, and the selector each of its stubs sends.
    package let stubRange: Range<UInt64>?
    package let stubSelectors: [UInt64: UnsafePointer<CChar>]
    /// `__objc_selrefs`.
    package let selectorReferenceRange: Range<UInt64>?
    /// `__objc_classrefs`: slots that hold a reference to a class.
    package let classReferenceRanges: [Range<UInt64>]
    /// `__objc_superrefs`: the class a super send in one of its methods starts
    /// above.
    package let superclassReferenceRange: Range<UInt64>?

    package static func of(_ table: ImageFunctionTable) -> ObjCImageSections {
        table.attachment(ObjCImageSections.self) { ObjCImageSections(table: table) }
    }

    private init(table: ImageFunctionTable) {
        var stubRange: Range<UInt64>?
        var stubSelectors: [UInt64: UnsafePointer<CChar>] = [:]
        var selectorReferenceRange: Range<UInt64>?
        var classReferenceRanges: [Range<UInt64>] = []
        var superclassReferenceRange: Range<UInt64>?
        let image = table.image.reader
        for section in table.sections {
            let sectionStart = UInt64(section.address)
            let sectionRange = sectionStart ..< sectionStart + UInt64(section.size)
            guard !sectionRange.isEmpty else { continue }
            switch section.sectionName {
            case "__objc_stubs":
                // MachOKit reads the stubs through an API per kind of reader.
                let stubs = if let machOImage = image.asMachOImage {
                    section.objcStubs(in: machOImage)
                } else if let machOFile = image.asMachOFile {
                    section.objcStubs(in: machOFile)
                } else {
                    nil as ObjCStubCollection?
                }
                guard let stubs else { continue }
                stubRange = sectionRange
                for objectiveCStub in stubs {
                    guard let selectorReference = objectiveCStub.selectorReference,
                          let selector = Self.selectorString(inSlotAt: selectorReference, of: table)
                    else { continue }
                    stubSelectors[objectiveCStub.stub.address] = selector
                }
            case "__objc_selrefs":
                selectorReferenceRange = sectionRange
            case "__objc_superrefs":
                superclassReferenceRange = sectionRange
            case "__objc_classrefs":
                classReferenceRanges.append(sectionRange)
            default:
                break
            }
        }
        self.stubRange = stubRange
        self.stubSelectors = stubSelectors
        self.selectorReferenceRange = selectorReferenceRange
        self.classReferenceRanges = classReferenceRanges
        self.superclassReferenceRange = superclassReferenceRange
    }

    package var approximateByteCount: Int {
        ApproximateSize.of(stubSelectors) + ApproximateSize.of(classReferenceRanges)
    }

    /// The selector string a selector reference slot of `table`'s image
    /// points at — the slot the cache builder or dyld has bound. Its length is
    /// not checked: a selector reference always points at a selector name.
    package static func selectorString(inSlotAt slotAddress: UInt64, of table: ImageFunctionTable) -> UnsafePointer<CChar>? {
        guard let selector = table.memory.pointer(at: table.runtimeAddress(ofUnslid: slotAddress)), selector != 0 else { return nil }
        return table.memory.typedPointer(to: CChar.self, at: selector, length: 1)
    }
}

/// The functions libobjc exports that a scan marks as runtime helpers:
/// memory management, which with the Swift runtime's outnumbers everything
/// else a function calls — in a macOS 27.2 shared cache, 26.5% of all direct
/// call targets.
package enum ObjCRuntimeHelperNames {
    private static let prefixes: [StaticString] = [
        "_objc_retain",
        "_objc_release",
        "_objc_autorelease",
        "_objc_storeStrong",
        "_objc_loadWeak",
        "_objc_storeWeak",
        "_objc_initWeak",
        "_objc_destroyWeak",
        "_objc_copyWeak",
        "_objc_moveWeak",
        "_objc_claimAutoreleasedReturnValue",
        "_objc_unsafeClaimAutoreleasedReturnValue",
    ]

    /// Whether the symbol named `name` is one of libobjc's runtime helpers.
    package static func isRuntimeHelper(_ name: UnsafePointer<CChar>) -> Bool {
        guard name[0] == 0x5F, name[1] == 0x6F else { return false }
        for prefix in prefixes {
            let matches = prefix.withUTF8Buffer { buffer in
                buffer.withMemoryRebound(to: CChar.self) { strncmp(name, $0.baseAddress!, buffer.count) == 0 }
            }
            if matches { return true }
        }
        return false
    }
}
