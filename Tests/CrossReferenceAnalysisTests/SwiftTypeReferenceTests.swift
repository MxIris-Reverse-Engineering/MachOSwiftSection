import Foundation
import Testing
import MachOKit
import Demangling
import ARM64InstructionDecoding
@testable import CrossReferenceAnalysis

/// Swift type references: calls to a type's metadata accessor and the
/// accessor's address, the address of its metadata, and the mangled names
/// code instantiates.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct SwiftTypeReferenceTests {
    private var analyzer: CrossReferenceAnalyzer { SharedAnalyzer.analyzer! }

    private func imageIndex(endingWith suffix: String) throws -> Int {
        try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix(suffix) }, "no image ending with \(suffix)")
    }

    private func identity(ofTypeWithKey key: String, inImageEndingWith suffix: String) throws -> SwiftTypeIdentity {
        let imageIndex = try imageIndex(endingWith: suffix)
        let location = try #require(analyzer.swiftTypeDescriptorLocations(withKey: key, inImageAt: imageIndex).first, "no type \(key)")
        return try #require(analyzer.swiftTypeIdentity(ofDescriptorAt: location))
    }

    /// The first nominal type a symbol names, as a key.
    private func key(ofSymbol symbol: String) -> String? {
        var mangled = Substring(symbol)
        if mangled.hasPrefix("_") { mangled = mangled.dropFirst() }
        guard let node = try? demangleAsNode(String(mangled)) else { return nil }
        return CrossReferenceAnalyzer.nominalKeys(in: node).first
    }

    /// Wherever SwiftUICore calls a metadata accessor a symbol names, the
    /// type the call is reported to reference is the one the symbol names.
    /// A type nested in a constrained extension is where the two came apart:
    /// its descriptor's context spells the extension's requirements, which
    /// is why a key comes from the descriptor's `…Mn` symbol.
    @Test func accessorCallsReferenceTheTypeTheAccessorNames() throws {
        let swiftUICore = try imageIndex(endingWith: "/SwiftUICore.framework/Versions/A/SwiftUICore")
        let table = analyzer.referenceTable(ofImageAt: swiftUICore)
        var callees: [UInt64: CodeLocation] = [:]
        for reference in table.references where reference.kind != .reference {
            if case .function(let location) = reference.target { callees[reference.instructionAddress] = location }
        }
        var compared = 0
        var disagreements: [String] = []
        for reference in table.references where reference.kind == .reference {
            guard case .swiftType(let descriptor) = reference.target,
                  let callee = callees[reference.instructionAddress],
                  let symbol = analyzer.symbolName(at: callee), symbol.hasSuffix("Ma")
            else { continue }
            compared += 1
            let key = analyzer.swiftTypeIdentity(ofDescriptorAt: descriptor)?.key
            if key != self.key(ofSymbol: symbol), disagreements.count < 5 { disagreements.append("\(symbol): \(key ?? "nil")") }
        }
        #expect(compared > 10000)
        #expect(disagreements.isEmpty, "\(disagreements)")
    }

    /// Wherever SwiftUICore builds an address with an `adrp` and the `add`
    /// right after it, and a symbol sits at that address, the type the
    /// reference is reported for is the one the symbol names: its metadata
    /// (`…N`) or its metadata accessor (`…Ma`).
    @Test func addressReferencesReferenceTheTypeAtTheAddress() throws {
        let swiftUICore = try imageIndex(endingWith: "/SwiftUICore.framework/Versions/A/SwiftUICore")
        let image = analyzer.images[swiftUICore]
        let slide = try #require(image.vmaddrSlide)
        let symbols = try #require(image.symbols64)
        var symbolsByAddress: [UInt64: [String]] = [:]
        for symbolIndex in 0 ..< symbols.numberOfSymbols {
            let entry = symbols.symbols[symbolIndex]
            guard entry.n_type & 0xE0 == 0, entry.n_type & 0x0E == 0x0E else { continue }
            let name = String(cString: symbols.stringBase.advanced(by: Int(entry.n_un.n_strx)))
            guard name.hasPrefix("_$s"), name.hasSuffix("N") || name.hasSuffix("Ma") else { continue }
            symbolsByAddress[entry.n_value, default: []].append(name)
        }
        func word(at address: UInt64) -> UInt32 {
            UnsafeRawPointer(bitPattern: Int(bitPattern: UInt(address)) &+ slide)!.load(as: UInt32.self)
        }
        var compared = 0
        var disagreements: [String] = []
        for reference in analyzer.referenceTable(ofImageAt: swiftUICore).references where reference.kind == .reference {
            guard case .swiftType(let descriptor) = reference.target,
                  let arithmetic = ARM64InstructionWord.addImmediate(word(at: reference.instructionAddress)),
                  let page = ARM64InstructionWord.addressMaterialization(word(at: reference.instructionAddress - 4), at: reference.instructionAddress - 4),
                  page.destination == arithmetic.source,
                  let names = symbolsByAddress[ARM64InstructionWord.adding(arithmetic.addend, to: page.address)]
            else { continue }
            compared += 1
            let key = analyzer.swiftTypeIdentity(ofDescriptorAt: descriptor)?.key
            if !names.contains(where: { self.key(ofSymbol: $0) == key }), disagreements.count < 5 { disagreements.append("\(names): \(key ?? "nil")") }
        }
        #expect(compared > 1000)
        #expect(disagreements.isEmpty, "\(disagreements)")
    }

    /// Foundation instantiates types from mangled names through its V2
    /// helper; each name is read from the `{ offset, length }` record the
    /// call passes in `x1`, lies in `__swift5_typeref`, and demangles.
    @Test func instantiationsReadTheirNamesFromTheRecord() throws {
        let foundation = try imageIndex(endingWith: "/Foundation.framework/Versions/C/Foundation")
        let section = try #require(analyzer.images[foundation].sections64.first { $0.sectionName == "__swift5_typeref" })
        let typeReferenceRange = UInt64(section.address) ..< UInt64(section.address) + UInt64(section.size)
        var names = Set<SwiftTypeName>()
        for reference in analyzer.referenceTable(ofImageAt: foundation).references {
            guard case .swiftTypeName(let name) = reference.target, case .mangledName(let location, _) = name else { continue }
            #expect(typeReferenceRange.contains(location.address))
            names.insert(name)
        }
        #expect(names.count > 500)
        let demangled = names.filter { !analyzer.swiftTypeKeys(in: $0).isEmpty }
        #expect(Double(demangled.count) / Double(max(names.count, 1)) > 0.98, "\(demangled.count) of \(names.count) demangle")
    }

    /// A query keeps a mangled name when one of its symbolic references
    /// leads to the type's descriptor, and demangles names only for a type a
    /// name may spell out. Checked against demangling every name of the
    /// image: for each type its names mention, the query keeps exactly the
    /// names whose demangled form mentions the type — no name mentions an
    /// ordinary type without a symbolic reference to it.
    ///
    /// For the four standard library types the query falls back on the same
    /// demangling this compares against, so they guard only against a
    /// symbolic reference leading to the wrong descriptor.
    @Test(arguments: ["/Foundation.framework/Versions/C/Foundation", "/SwiftData.framework/Versions/A/SwiftData"])
    func queriesKeepExactlyTheNamesThatMentionTheType(imageSuffix: String) throws {
        let imageIndex = try imageIndex(endingWith: imageSuffix)
        let slide = try #require(analyzer.images[imageIndex].vmaddrSlide)
        var keysByName: [SwiftTypeName: Set<String>] = [:]
        var mentions: [CodeLocation: Int] = [:]
        for reference in analyzer.referenceTable(ofImageAt: imageIndex).references {
            guard case .swiftTypeName(let name) = reference.target, case .mangledName(let location, let length) = name, keysByName[name] == nil else { continue }
            // A name that does not demangle has nothing to compare against.
            let keys = analyzer.swiftTypeKeys(in: name)
            guard !keys.isEmpty else { continue }
            keysByName[name] = Set(keys)
            // The descriptors the name's symbolic references lead to.
            let bytes = UnsafePointer<UInt8>(bitPattern: Int(bitPattern: UInt(location.address)) &+ slide)!
            var position = 0
            while position < length {
                let byte = bytes[position]
                if byte == 0x01 || byte == 0x02 {
                    let field = UInt(bitPattern: bytes + position + 1)
                    var descriptor = UInt(bitPattern: Int(bitPattern: field) &+ Int(UnsafeRawPointer(bytes + position + 1).loadUnaligned(as: Int32.self)))
                    if byte == 0x02 { descriptor = UInt(UnsafeRawPointer(bitPattern: descriptor)!.loadUnaligned(as: UInt64.self) & 0x7FFF_FFFF_FFFF) }
                    if let descriptorLocation = analyzer.location(ofDescriptorAtRuntimeAddress: descriptor) { mentions[descriptorLocation, default: 0] += 1 }
                }
                position += byte >= 0x01 && byte <= 0x17 ? 5 : (byte >= 0x18 && byte <= 0x1F ? 9 : 1)
            }
        }
        // The types the names refer to most — protocols have no type context
        // descriptor and drop out — and four the standard library spells out.
        var identities = mentions.sorted { $0.value > $1.value }.compactMap { analyzer.swiftTypeIdentity(ofDescriptorAt: $0.key) }.prefix(40).map { $0 }
        let standardLibrary = try self.imageIndex(endingWith: "/usr/lib/swift/libswiftCore.dylib")
        for key in ["Sa", "Sq", "SD", "SS"] {
            let location = try #require(analyzer.swiftTypeDescriptorLocations(withKey: key, inImageAt: standardLibrary).first, "no \(key)")
            identities.append(try #require(analyzer.swiftTypeIdentity(ofDescriptorAt: location)))
        }
        #expect(identities.count >= 24)
        #expect(identities.contains { SwiftTypeQuery.mayBeSpelledOut($0.key) })
        #expect(identities.contains { !SwiftTypeQuery.mayBeSpelledOut($0.key) })
        var mismatches: [String] = []
        for identity in identities {
            let query = SwiftTypeQuery(identity: identity, analyzer: analyzer)
            for (name, keys) in keysByName where query.matches(.swiftTypeName(name)) != keys.contains(identity.key) {
                if mismatches.count < 5 { mismatches.append("\(identity.key) in \(keys.sorted())") }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    /// The macOS and the Mac Catalyst SwiftUI define the same types. A query
    /// for the macOS one finds nothing in the Catalyst image, which uses its
    /// own; the Catalyst one's query finds its references there — this class
    /// also as an Objective-C class.
    @Test func queriesTellApartTypesOfTheSameKey() throws {
        let macOS = try identity(ofTypeWithKey: "7SwiftUI13PinnedBarViewC", inImageEndingWith: "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI")
        let catalyst = try identity(ofTypeWithKey: "7SwiftUI13PinnedBarViewC", inImageEndingWith: "/System/iOSSupport/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI")
        #expect(macOS.objectiveCClassLocation != nil)
        #expect(macOS.descriptorLocation != catalyst.descriptorLocation)
        let catalystImage = catalyst.descriptorLocation.imageIndex
        #expect(analyzer.references(toSwiftType: macOS, inImageAt: catalystImage).isEmpty)
        #expect(!analyzer.references(toSwiftType: catalyst, inImageAt: catalystImage).isEmpty)
    }

    /// A type prefilter may drop only images that cannot reference the type.
    /// Few cache images keep a Swift symbol among their undefined symbols, so
    /// the images that can bind to the defining image are what is kept:
    /// SharedWithYou imports nothing for `URL` and calls its metadata
    /// accessor all the same, through a GOT stub the cache builder bound.
    ///
    /// The dropped images are sampled, every sixteenth: a Debug build scans
    /// the whole cache in minutes, not seconds.
    @Test(arguments: zip(
        ["/Foundation.framework/Versions/C/Foundation", "/SwiftUICore.framework/Versions/A/SwiftUICore", "/Foundation.framework/Versions/C/Foundation"],
        ["10Foundation3URLV", "7SwiftUI4TextV", "10Foundation11JSONEncoderC"]
    ))
    func typePrefilterKeepsEveryReferencingImage(imageSuffix: String, key: String) throws {
        let identity = try identity(ofTypeWithKey: key, inImageEndingWith: imageSuffix)
        let everyImage = Array(analyzer.images.indices)
        let kept = analyzer.imageIndices(referencingSwiftType: identity, among: everyImage)
        #expect(kept.contains(identity.descriptorLocation.imageIndex))
        let importers = kept.filter { $0 != identity.descriptorLocation.imageIndex }
        #expect(!imagesReferencing(identity, among: Array(importers.prefix(64))).isEmpty)
        let droppedSample = Set(everyImage).subtracting(kept).sorted().enumerated().filter { $0.offset % 16 == 0 }.map(\.element)
        let missed = imagesReferencing(identity, among: droppedSample)
        #expect(missed.isEmpty, "prefilter dropped referencing images: \(missed.sorted().prefix(5).map { analyzer.imagePaths[$0] })")
    }

    private func imagesReferencing(_ identity: SwiftTypeIdentity, among imageIndices: [Int]) -> Set<Int> {
        let found = ImageIndexCollector()
        let analyzer = analyzer
        DispatchQueue.concurrentPerform(iterations: imageIndices.count) { position in
            if !analyzer.references(toSwiftType: identity, inImageAt: imageIndices[position]).isEmpty { found.insert(imageIndices[position]) }
        }
        return found.indices
    }
}
