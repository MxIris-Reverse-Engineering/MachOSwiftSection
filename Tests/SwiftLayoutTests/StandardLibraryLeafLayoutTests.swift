import Foundation
import Testing
import MachOKit
import MachOFoundation
import Demangling
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout

/// The standard library's own images, read out of the host's dyld shared
/// cache as files — the way `swift-section` reads a system image offline. A
/// separate type on purpose: a `@Suite(.enabled(if:))` condition that reads a
/// static of the suite it decorates is a circular macro reference.
enum HostStandardLibraryImages {
    static let libswiftCorePath = "/usr/lib/swift/libswiftCore.dylib"

    /// Declares fields of `Builtin.Job`, `Builtin.Executor` and
    /// `Builtin.RawUnsafeContinuation`, yet carries no builtin leaf record:
    /// the compiler emits those for the standard library alone.
    static let concurrencyPath = "/usr/lib/swift/libswift_Concurrency.dylib"

    static var isAvailable: Bool { FullDyldCache.cachedHost != nil }

    static func image(atPath path: String) throws -> MachOFile {
        let hostCache = try #require(FullDyldCache.cachedHost, "no host dyld shared cache")
        return try #require(hostCache.machOFile(by: .path(path)), "the host dyld shared cache has no \(path)")
    }
}

/// What the static engine answers for the compiler's builtin leaf types — the
/// layouts every standard library type bottoms out in — checked against the
/// two authorities the binaries carry: libswiftCore's `__swift5_builtin` leaf
/// records and the runtime's value-witness tables. The last test turns the
/// same check on `KnownLayoutTable`, whose frozen layouts must be exactly what
/// libswiftCore's own metadata computes.
@Suite(.enabled(if: HostStandardLibraryImages.isAvailable))
struct StandardLibraryLeafLayoutTests {
    /// The five facts a value-witness table records about a layout, compared as
    /// one value so a mismatch prints both sides in full.
    private struct WitnessedLayout: Equatable, CustomStringConvertible {
        let size: Int
        let stride: Int
        let alignment: Int
        let extraInhabitantCount: Int
        let isBitwiseTakable: Bool

        init(_ staticLayout: StaticTypeLayout) {
            self.size = staticLayout.size
            self.stride = staticLayout.stride
            self.alignment = staticLayout.alignment
            self.extraInhabitantCount = staticLayout.extraInhabitantCount
            self.isBitwiseTakable = staticLayout.isBitwiseTakable
        }

        /// The live value-witness table of `runtimeType`: the runtime's own answer.
        init(runtimeLayoutOf runtimeType: Any.Type) throws {
            let metadata = try MetadataWrapper.resolve(at: unsafeBitCast(runtimeType, to: UnsafeRawPointer.self), in: .inProcess)
            let valueWitnessTable = try metadata.valueWitnessTable(in: .inProcess)
            self.size = Int(valueWitnessTable.layout.size)
            self.stride = Int(valueWitnessTable.layout.stride)
            self.alignment = Int(valueWitnessTable.layout.flags.alignment)
            self.extraInhabitantCount = Int(valueWitnessTable.layout.numExtraInhabitants)
            self.isBitwiseTakable = valueWitnessTable.layout.flags.isBitwiseTakable
        }

        var description: String {
            "(size: \(size), stride: \(stride), alignment: \(alignment), "
                + "extraInhabitantCount: 0x\(String(extraInhabitantCount, radix: 16)), "
                + "isBitwiseTakable: \(isBitwiseTakable))"
        }
    }

    /// A builtin leaf as libswiftCore's `__swift5_builtin` section records it.
    struct RecordedLeaf: Sendable, CustomTestStringConvertible {
        let builtinName: String
        let layout: StaticTypeLayout
        var testDescription: String { builtinName }
    }

    /// A `_Concurrency` type whose only stored field is a builtin leaf that no
    /// image records, so the engine answers the leaf from what it knows.
    enum ConcurrencyLeafHolder: CaseIterable, Sendable, CustomTestStringConvertible {
        case unownedJob
        case unownedSerialExecutor
        case unsafeContinuation

        var qualifiedTypeName: String {
            switch self {
            case .unownedJob: "Swift.UnownedJob"
            case .unownedSerialExecutor: "Swift.UnownedSerialExecutor"
            case .unsafeContinuation: "Swift.UnsafeContinuation"
            }
        }

        var runtimeType: Any.Type {
            switch self {
            case .unownedJob: UnownedJob.self
            case .unownedSerialExecutor: UnownedSerialExecutor.self
            case .unsafeContinuation: UnsafeContinuation<Int, Never>.self
            }
        }

        var testDescription: String { qualifiedTypeName }
    }

    private func structDescriptor(named qualifiedTypeName: String, in machO: MachOFile) throws -> StructDescriptor? {
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard
                case .struct(let structDescriptor)? = contextDescriptor.typeContextDescriptorWrapper,
                (try? SymbolicDemangler.demangleContext(for: contextDescriptor, in: machO.context))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)) == qualifiedTypeName
            else { continue }
            return structDescriptor
        }
        return nil
    }

    /// The builtin type name a builtin mangling demangles to (`Bi1_` →
    /// `Builtin.Int1`), the spelling both the resolver and the index key on.
    private func builtinTypeName(of builtinNode: Node) throws -> String {
        let builtinTypeNameNode = builtinNode.kind == .type ? builtinNode.firstChild : builtinNode
        return try #require(builtinTypeNameNode?.text, "\(builtinNode) is not a builtin type")
    }

    // The literals are what libswiftCore's records carry, read from the raw
    // section bytes; builtin leaf layouts are fixed by the ABI.
    @Test("A leaf libswiftCore records is found under the builtin's own name", arguments: [
        RecordedLeaf(builtinName: "Builtin.Int1", layout: StaticTypeLayout(size: 1, stride: 1, alignmentMask: 0, extraInhabitantCount: 254, isBitwiseTakable: true)),
        RecordedLeaf(builtinName: "Builtin.FPIEEE16", layout: StaticTypeLayout(size: 2, stride: 2, alignmentMask: 1, extraInhabitantCount: 0, isBitwiseTakable: true)),
        RecordedLeaf(builtinName: "Builtin.IntLiteral", layout: StaticTypeLayout(size: 16, stride: 16, alignmentMask: 7, extraInhabitantCount: 0x7FFF_FFFF, isBitwiseTakable: true)),
        RecordedLeaf(builtinName: "Builtin.UnsafeValueBuffer", layout: StaticTypeLayout(size: 24, stride: 24, alignmentMask: 7, extraInhabitantCount: 0, isBitwiseTakable: false)),
    ])
    func recordedLeafIsFoundByBuiltinName(recordedLeaf: RecordedLeaf) throws {
        let builtinIndex = try BuiltinTypeLayoutIndex(machO: HostStandardLibraryImages.image(atPath: HostStandardLibraryImages.libswiftCorePath))
        #expect(builtinIndex.layout(forTypeName: recordedLeaf.builtinName) == recordedLeaf.layout)
    }

    /// Another image's field of one of these types reaches libswiftCore through
    /// the dependency closure, where the type's only stored field is a leaf
    /// that libswiftCore's records alone describe.
    @Test("A standard library type over a leaf only libswiftCore records lays out like the runtime", arguments: [
        "s7Float16V",
        "s12StaticBigIntV",
    ])
    func standardLibraryTypeOverRecordedLeafMatchesRuntime(mangledTypeName: String) throws {
        let runtimeType = try #require(_typeByName(mangledTypeName), "the runtime has no \(mangledTypeName)")
        let runtimeLayout = try WitnessedLayout(runtimeLayoutOf: runtimeType)
        let universe = try ImageUniverse.dependencyClosure(root: HostStandardLibraryImages.image(atPath: HostStandardLibraryImages.concurrencyPath))
        let staticLayout = try StaticTypeLayoutResolver(imageUniverse: universe)
            .layout(forTypeNode: demangleAsNode(mangledTypeName, isType: true), in: universe.rootImage)
        #expect(WitnessedLayout(staticLayout) == runtimeLayout)
    }

    /// The leaves the engine must answer itself — every image but libswiftCore
    /// declares builtin fields without recording them — must agree with
    /// libswiftCore's record of the same leaf.
    @Test("A leaf answered without a record matches libswiftCore's record of it", arguments: [
        "Bi1_", "Bi8_", "Bi16_", "Bi32_", "Bi64_", "Bi128_", "Bw",
        "Bf16_", "Bf32_", "Bf64_",
        "Bp", "Bo", "Bb", "BO",
    ])
    func leafAnsweredWithoutRecordMatchesLibswiftCoresRecord(builtinMangling: String) throws {
        let builtinNode = try demangleAsNode(builtinMangling, isType: true)
        let builtinName = try builtinTypeName(of: builtinNode)
        let libswiftCoreIndex = try BuiltinTypeLayoutIndex(machO: HostStandardLibraryImages.image(atPath: HostStandardLibraryImages.libswiftCorePath))
        let recordedLayout = try #require(libswiftCoreIndex.layout(forTypeName: builtinName), "libswiftCore records no \(builtinName)")

        let universe = try ImageUniverse.singleImage(HostStandardLibraryImages.image(atPath: HostStandardLibraryImages.concurrencyPath))
        let answeredLayout = try StaticTypeLayoutResolver(imageUniverse: universe).layout(forTypeNode: builtinNode, in: universe.rootImage)
        #expect(answeredLayout == recordedLayout)
    }

    @Test("A concurrency type over a leaf no image records lays out like the runtime", arguments: ConcurrencyLeafHolder.allCases)
    func concurrencyLeafHolderMatchesRuntime(holder: ConcurrencyLeafHolder) throws {
        let runtimeLayout = try WitnessedLayout(runtimeLayoutOf: holder.runtimeType)
        let concurrency = try HostStandardLibraryImages.image(atPath: HostStandardLibraryImages.concurrencyPath)
        let structDescriptor = try #require(try structDescriptor(named: holder.qualifiedTypeName, in: concurrency), "libswift_Concurrency declares no \(holder.qualifiedTypeName)")
        let staticLayout = try StaticLayoutCalculator(machO: concurrency).typeLayout(ofStruct: structDescriptor)
        #expect(WitnessedLayout(staticLayout) == runtimeLayout)
    }

    /// `Builtin.DefaultActorStorage` is the inline storage of a default actor,
    /// `Builtin.NonDefaultDistributedActorStorage` that of a distributed actor
    /// with a custom executor; the compiler gives both as an artificial stored
    /// field. IRGen lowers both as `NumWords_DefaultActor` /
    /// `NumWords_NonDefaultDistributedActor` (12) machine words at twice the
    /// pointer alignment, with no spare bits.
    @Test("An actor's inline storage is twelve words at twice the pointer alignment", arguments: ["BD", "Bd"])
    func actorStorageLeaf(builtinMangling: String) throws {
        let universe = try ImageUniverse.singleImage(HostStandardLibraryImages.image(atPath: HostStandardLibraryImages.concurrencyPath))
        let layout = try StaticTypeLayoutResolver(imageUniverse: universe)
            .layout(forTypeNode: demangleAsNode(builtinMangling, isType: true), in: universe.rootImage)
        #expect(layout == StaticTypeLayout(size: 96, stride: 96, alignmentMask: 15, extraInhabitantCount: 0, isBitwiseTakable: true))
    }

    /// Each libswiftCore struct the table names is laid out from its own field
    /// records down to libswiftCore's leaf records. A field whose type the
    /// table also names (`Character`'s `String`) is answered by the table; that
    /// entry is checked at its own top level, so every entry rests on the
    /// binary.
    @Test("Every frozen layout in KnownLayoutTable is what libswiftCore's own metadata computes")
    func knownLayoutTableAgreesWithLibswiftCore() throws {
        let libswiftCore = try HostStandardLibraryImages.image(atPath: HostStandardLibraryImages.libswiftCorePath)
        let calculator = try StaticLayoutCalculator(machO: libswiftCore)
        var comparedTypeNames: Set<String> = []
        for contextDescriptor in try libswiftCore.swift.contextDescriptors {
            guard
                case .struct(let structDescriptor)? = contextDescriptor.typeContextDescriptorWrapper,
                let qualifiedTypeName = (try? SymbolicDemangler.demangleContext(for: contextDescriptor, in: libswiftCore.context))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                let frozenLayout = KnownLayoutTable.layout(forFullyQualifiedTypeName: qualifiedTypeName)
            else { continue }
            comparedTypeNames.insert(qualifiedTypeName)
            do {
                let computedLayout = try calculator.typeLayout(ofStruct: structDescriptor)
                #expect(computedLayout == frozenLayout, "\(qualifiedTypeName): libswiftCore computes \(computedLayout), the table says \(frozenLayout)")
            } catch {
                Issue.record("\(qualifiedTypeName): libswiftCore's metadata does not lay out — \(error)")
            }
        }
        // A table that no longer meets the libswiftCore types it names would
        // pass vacuously.
        #expect(comparedTypeNames.isSuperset(of: [
            "Swift.Bool", "Swift.Int", "Swift.Double", "Swift.String", "Swift.Character",
            "Swift.Array", "Swift.Dictionary", "Swift.Set",
            "Swift.UnsafePointer", "Swift.UnsafeRawBufferPointer", "Swift.Unmanaged",
        ]), "compared only \(comparedTypeNames.sorted())")
    }
}
