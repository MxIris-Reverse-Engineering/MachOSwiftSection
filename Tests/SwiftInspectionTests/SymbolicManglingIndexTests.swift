import Foundation
import Testing
import MachOKit
import MachOObjCSection
@testable import Demangling
@testable import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@testable import MachOTestingSupport
import MachOFixtureSupport
@testable @_spi(Internals) import SwiftInspection

/// The decoding layer of evolution proposal `symbolic-mangling-symbol-index`:
/// `SymbolicManglingIndex` pairs every symbolic reference in the mangled names
/// an image's symbolic-mangling symbols name with the referent the symbol
/// spells for it.
///
/// Anchored on symbols of one AppKit source file, whose private discriminator
/// is read from `FontPanelBIUSPopUpButton`'s Objective-C runtime name
/// (`_TtC6AppKitP33_<discriminator>24FontPanelBIUSPopUpButton`) so the
/// expectations follow the running system instead of pinning one build's hash.
@Suite(.serialized)
struct SymbolicManglingIndexTests {
    private static let appKitPath = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"

    private static var runsOnMacOS26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor symbols ship with macOS 26's AppKit"))
    func anchorSymbolsPairInTheSystemCache() throws {
        let machOFile = try Self.appKitFileInSystemCache()
        try Self.expectAnchorSymbolsPair(in: machOFile)
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor symbols ship with macOS 26's AppKit"))
    func anchorSymbolsPairInProcess() throws {
        let machOImage = try Self.loadedAppKitImage()
        try Self.expectAnchorSymbolsPair(in: machOImage)
    }

    /// The pairing rests on the name spelling one referent per reference, in
    /// order; a symbol that fails to pair means that reading was wrong.
    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor symbols ship with macOS 26's AppKit"))
    func everySymbolPairsWithItsMangledName() throws {
        let machOFile = try Self.appKitFileInSystemCache()
        let machOImage = try Self.loadedAppKitImage()

        #expect(SymbolicManglingIndex.shared.unpairedSymbolCount(in: machOFile) == 0)
        #expect(SymbolicManglingIndex.shared.unpairedSymbolCount(in: machOImage) == 0)
        #expect(SymbolicManglingIndex.shared.references(in: machOFile).count == SymbolicManglingIndex.shared.references(in: machOImage).count)
    }

    /// A default associated type witness's mangled name opens with a `0xFF`
    /// role marker its symbol spells as a prefix instead; AppKit has none, so
    /// SwiftUICore covers that role. Also the acceptance evidence for the
    /// proposal's memory note: what the paired references cost per image.
    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor symbols ship with macOS 26's AppKit"))
    func referenceCensusOfSystemCacheImages() throws {
        let cache = try DyldCache(path: .current)
        var censusLines: [String] = []
        for imageName in [MachOImageName.AppKit, .SwiftUICore] {
            let machOFile = try #require(cache.machOFile(named: imageName), "the running system's cache has no \(imageName)")
            let symbols = try #require(SymbolicManglingIndex.shared.symbols(in: machOFile))
            let references = SymbolicManglingIndex.shared.references(in: machOFile)
            var referenceCountByKind: [UInt8: Int] = [:]
            var defaultAssociatedTypeWitnessReferenceCount = 0
            for reference in references {
                referenceCountByKind[reference.kind.rawValue, default: 0] += 1
                if SymbolicManglingSymbolName(symbols[reference.symbolPosition].name)?.role == .defaultAssociatedTypeWitness {
                    defaultAssociatedTypeWitnessReferenceCount += 1
                }
            }
            let kindSummary = referenceCountByKind.sorted { $0.key < $1.key }.map { String(format: "0x%02X: %d", $0.key, $0.value) }.joined(separator: ", ")
            let referenceByteCount = references.count * (MemoryLayout<SymbolicManglingReference>.stride + MemoryLayout<UInt32>.stride)
            censusLines.append("\(imageName): \(references.count) references (\(kindSummary)), \(defaultAssociatedTypeWitnessReferenceCount) from default assoc type, \(referenceByteCount) bytes")
            #expect(SymbolicManglingIndex.shared.unpairedSymbolCount(in: machOFile) == 0, "\(imageName) has symbols that do not pair")
            if imageName == .SwiftUICore {
                #expect(defaultAssociatedTypeWitnessReferenceCount > 0, "SwiftUICore's default associated type witnesses should pair past their 0xFF marker")
            }
        }
        #expect(MemoryLayout<SymbolicManglingReference>.stride == 24)
        print("Symbolic-mangling reference census —\n" + censusLines.joined(separator: "\n"))
    }

    /// A symbol's referents come out of one mangler, so a later one may use a
    /// substitution standing for part of an earlier one: demangled one by one
    /// some fail, demangled together every symbol's must succeed. The count of
    /// the former pins why the index never demangles a referent alone.
    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor symbols ship with macOS 26's AppKit"))
    func everySymbolsReferentsDemangleTogether() throws {
        let machOFile = try Self.appKitFileInSystemCache()
        let symbols = try #require(SymbolicManglingIndex.shared.symbols(in: machOFile))
        var decodedSymbolCount = 0
        var referentsFailingAloneCount = 0
        var failures: [String] = []
        for position in symbols.indices {
            guard let symbolName = SymbolicManglingSymbolName(symbols[position].name), !symbolName.referentManglings.isEmpty else { continue }
            guard let referentNodes = SymbolicManglingIndex.shared.referentNodes(ofSymbolAt: position, in: machOFile) else {
                failures.append(symbols[position].name)
                continue
            }
            decodedSymbolCount += 1
            for (referentMangling, referentNode) in zip(symbolName.referentManglings, referentNodes) {
                if (try? demangleAsNodeTransient("$s" + referentMangling))?.children.first?.print(using: .default) != referentNode.print(using: .default) {
                    referentsFailingAloneCount += 1
                }
            }
        }
        #expect(decodedSymbolCount > 1000, "AppKit on macOS 26 carries thousands of symbolic-mangling symbols with referents")
        #expect(failures.isEmpty, "\(failures.count) symbols' referents do not demangle together:\n\(failures.prefix(20).joined(separator: "\n"))")
        #expect(referentsFailingAloneCount > 0, "no referent leans on an earlier one; the joint demangling would be unproven")
    }

    /// Every `_symbolic` symbol is an answer the compiler wrote down in
    /// advance: the referent of a direct reference to a type or protocol
    /// descriptor is that descriptor's full name. `SymbolicDemangler` builds
    /// the same name from the descriptors themselves, so the two must agree.
    ///
    /// Except, for now, for a type declared inside a function body: it sits in
    /// an anonymous context standing for that function, which the compiler
    /// spells (`DeferralState #1 in …deferCompletionUntil() -> () -> ()`) and
    /// `SymbolicDemangler` drops, as it dropped a private type's discriminator
    /// before the symbolic-mangling index. Recorded in the proposal's decision
    /// log as a known difference, not fixed there.
    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor symbols ship with macOS 26's AppKit"))
    func descriptorBuiltNamesAgreeWithTheCompilersSpelling() throws {
        let machOFile = try Self.appKitFileInSystemCache()
        var visitedReferencedOffsets: Set<Int> = []
        var comparedCount = 0
        var mismatches: [String] = []
        var localTypeMismatches: [String] = []
        for reference in SymbolicManglingIndex.shared.references(in: machOFile) where reference.kind == .directContextDescriptor {
            guard visitedReferencedOffsets.insert(reference.referencedOffset).inserted else { continue }
            let context: ContextDescriptorWrapper = try .resolve(from: reference.referencedOffset, in: machOFile)
            switch context {
            case .type, .protocol:
                break
            default:
                continue
            }
            let referentNode = try #require(
                SymbolicManglingIndex.shared.referentNode(of: reference, in: machOFile),
                "the referent of the reference at \(reference.referenceOffset) does not demangle"
            )
            let compilerSpelledName = Self.printedName(of: referentNode)
            let descriptorBuiltName = try Self.printedName(of: SymbolicDemangler.demangleContext(for: context, in: machOFile))
            comparedCount += 1
            if descriptorBuiltName != compilerSpelledName {
                let mismatch = "descriptor \(descriptorBuiltName), compiler \(compilerSpelledName)"
                if referentNode.first(of: .localDeclName) != nil {
                    localTypeMismatches.append(mismatch)
                } else {
                    mismatches.append(mismatch)
                }
            }
        }
        #expect(comparedCount > 500, "AppKit on macOS 26 references hundreds of its own types and protocols directly")
        #expect(mismatches.isEmpty, "\(mismatches.count) of \(comparedCount) differ:\n\(mismatches.prefix(40).joined(separator: "\n"))")
        withKnownIssue("SymbolicDemangler drops the function context of a type declared in a function body") {
            #expect(localTypeMismatches.isEmpty, "\(localTypeMismatches.count) local types differ:\n\(localTypeMismatches.joined(separator: "\n"))")
        }
    }

    // MARK: - Anchor symbols

    private static func expectAnchorSymbolsPair(in machO: some MachOSwiftSectionRepresentableWithCache & ObjCImplementationClassReading) throws {
        let discriminator = try #require(try discriminatorFromObjCRuntimeName(in: machO))
        let fontPanelButton = "6AppKit24FontPanelBIUSPopUpButton33\(discriminator)LLC"
        let textShadowViewController = "6AppKit24TextShadowViewController33\(discriminator)LLC"
        let textShadowViewControllerDelegate = "6AppKit32TextShadowViewControllerDelegate33\(discriminator)LLP"
        let fontPanelButtonDescriptor = try #require(try classDescriptor(named: "FontPanelBIUSPopUpButton", in: machO))
        let textShadowViewControllerDescriptor = try #require(try classDescriptor(named: "TextShadowViewController", in: machO))
        let symbols = try #require(SymbolicManglingIndex.shared.symbols(in: machO))

        func onlyReference(ofSymbolNamed symbolName: String, mentioning identifier: String) throws -> (position: Int, reference: SymbolicManglingReference) {
            let position = try #require(
                symbols.position(ofSymbolNamed: symbolName),
                "\(symbolName) was not collected; the symbols mentioning \(identifier) are:\n\(symbols.map(\.name).filter { $0.contains(identifier) }.joined(separator: "\n"))"
            )
            let references = SymbolicManglingIndex.shared.references(in: machO).filter { $0.symbolPosition == position }
            try #require(references.count == 1, "\(symbolName) should pair exactly one reference, found \(references.count)")
            return (position, references[0])
        }

        func referentName(of reference: SymbolicManglingReference) throws -> String {
            try printedName(of: #require(SymbolicManglingIndex.shared.referentNode(of: reference, in: machO)))
        }

        // The type name a field descriptor records for its own type; the
        // reference is the mangled name's first byte.
        let fontPanelButtonSymbol = try onlyReference(ofSymbolNamed: "_symbolic _____ \(fontPanelButton)", mentioning: "FontPanelBIUSPopUpButton")
        #expect(fontPanelButtonSymbol.reference.kind == .directContextDescriptor)
        #expect(fontPanelButtonSymbol.reference.referencedOffset == fontPanelButtonDescriptor.offset)
        #expect(fontPanelButtonSymbol.reference.referenceOffset == symbols[fontPanelButtonSymbol.position].offset)
        #expect(try referentName(of: fontPanelButtonSymbol.reference) == "AppKit.(FontPanelBIUSPopUpButton in \(discriminator))")
        let fontPanelButtonNode = try #require(SymbolicManglingIndex.shared.referentNode(forContextDescriptorAt: fontPanelButtonDescriptor.offset, in: machO))
        #expect(printedName(of: fontPanelButtonNode) == "AppKit.(FontPanelBIUSPopUpButton in \(discriminator))")

        let textShadowViewControllerSymbol = try onlyReference(ofSymbolNamed: "_symbolic _____ \(textShadowViewController)", mentioning: "TextShadowViewController")
        #expect(textShadowViewControllerSymbol.reference.kind == .directContextDescriptor)
        #expect(textShadowViewControllerSymbol.reference.referencedOffset == textShadowViewControllerDescriptor.offset)
        #expect(try referentName(of: textShadowViewControllerSymbol.reference) == "AppKit.(TextShadowViewController in \(discriminator))")

        // `weak var delegate: TextShadowViewControllerDelegate?`. An `@objc`
        // protocol is referenced through its Objective-C protocol reference,
        // even when Swift declares it; the sixth underscore belongs to `_p`.
        let delegateSymbol = try onlyReference(ofSymbolNamed: "_symbolic ______pSgXw \(textShadowViewControllerDelegate)", mentioning: "TextShadowViewControllerDelegate")
        #expect(delegateSymbol.reference.kind == .objectiveCProtocol)
        #expect(delegateSymbol.reference.referenceOffset == symbols[delegateSymbol.position].offset)
        #expect(try referentName(of: delegateSymbol.reference) == "AppKit.(TextShadowViewControllerDelegate in \(discriminator))")

        // The offset query finds the reference from where it points.
        #expect(SymbolicManglingIndex.shared.references(to: textShadowViewControllerDescriptor.offset, in: machO) == [textShadowViewControllerSymbol.reference])
    }

    // MARK: - Helpers

    private static func printedName(of node: Node) -> String {
        var unwrappedNode = node
        while unwrappedNode.kind == .global || unwrappedNode.kind == .type || unwrappedNode.kind == .typeMangling, let child = unwrappedNode.children.first {
            unwrappedNode = child
        }
        return unwrappedNode.print(using: .default)
    }

    /// The test process does not link AppKit, so it has to be mapped before a
    /// `MachOImage` can be made of it.
    private static func loadedAppKitImage() throws -> MachOImage {
        try #require(dlopen(appKitPath, RTLD_LAZY) != nil, "AppKit could not be loaded into the test process")
        return try #require(MachOImage(name: "AppKit"))
    }

    private static func appKitFileInSystemCache() throws -> MachOFile {
        let cache = try DyldCache(path: .current)
        return try #require(cache.machOFile(named: .AppKit), "the running system's cache has no AppKit")
    }

    private static func classDescriptor(named name: String, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor? {
        for typeContextDescriptor in try machO.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor else { continue }
            if try classDescriptor.name(in: machO) == name {
                return classDescriptor
            }
        }
        return nil
    }

    /// The discriminator `FontPanelBIUSPopUpButton`'s Objective-C runtime name
    /// carries, demangled rather than sliced out of the string.
    private static func discriminatorFromObjCRuntimeName(in machO: some ObjCImplementationClassReading) throws -> String? {
        for classObject in machO.objcImplementationClassObjects() ?? [] {
            guard let readOnlyData = machO.instanceReadOnlyData(of: classObject),
                  let runtimeName = machO.className(of: readOnlyData),
                  runtimeName.hasPrefix("_TtC6AppKitP33_"),
                  runtimeName.hasSuffix("FontPanelBIUSPopUpButton")
            else { continue }
            let node = try demangleAsNodeTransient(runtimeName)
            return node.first(of: .privateDeclName)?.children.first?.text
        }
        return nil
    }
}
