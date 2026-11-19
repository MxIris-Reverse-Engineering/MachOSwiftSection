import Foundation
import FoundationToolbox
import MachOKit
@_spi(Internals) import MachOAddressResolution
@_spi(Internals) import MachOSymbols
import MachOFoundation
import SwiftSymbols
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection
@_spi(Internals) import MachOCaches

@Loggable(.fileprivate, subsystem: "com.machoswiftsection.swift-thunk-analysis", category: "MachOThunkEnvironment")
fileprivate protocol MachOThunkEnvironmentLogging {}

/// The evaluator's view of one Mach-O: what each call target is, and what a
/// pointer-sized word holds.
///
/// ## Naming a call target
///
/// A thunk's calls go one of four ways, and the order below is the order
/// they are tried:
///
/// 1. **A metadata accessor in this image** — `MetadataAccessorIndex` maps
///    the address to the descriptor whose accessor it is.
/// 2. **A local symbol.** An unstripped image names two kinds of function
///    the index does not: the compiler's per-image copy of a runtime helper
///    (`__swift_instantiateConcreteTypeFromMangledNameV2`), and a lazily
///    specialized accessor emitted for one concrete instantiation
///    (`$s15Synchronization5MutexVyShySSGGMa`, `Mutex<Set<String>>`), whose
///    symbol spells the whole type and which takes no arguments.
/// 3. **A stub.** Inside a shared cache every cross-image call goes through
///    a four-instruction stub (`adrp x17` / `add x17` / `ldr x16, [x17]` /
///    `braa x16, x17`; a standalone binary's is `adrp` / `ldr` / `br`) whose
///    load names a GOT slot — or, when the cache is too large for a `bl` to
///    reach across its subcaches, through a **stub island**: `adrp x16` /
///    `add x16` / `br x16`, a trampoline the cache builder places *between*
///    images that computes its target outright and loads nothing (iOS
///    device caches; islands may chain). An island is recognized by that
///    shape and its target classified again, up to a fixed number of hops. The slot is either a **bind** — a symbol name,
///    the standalone case — or, inside a cache where dyld already resolved
///    every bind, a **rebase** to the callee's address in some other image.
///    A bound name is classified directly when it is a runtime entry point
///    (`_swift_getWitnessTable`, `___swift_instantiateConcreteTypeFromMangledNameV2`),
///    and otherwise looked for in the export tries of the images the root
///    links, located through the search paths (``DependencyImageResolver``)
///    — a third-party app's `Mutex<…>` field calls
///    `libswiftSynchronization/_$s15Synchronization5MutexVMa` this way. A
///    rebase target is located through the cache's image table, and the
///    image it lands in answers through its own accessor index or its
///    export trie.
/// 4. Anything else is ``ThunkCallee/unknown``. The availability check is
///    one such: `__isPlatformVersionAtLeast` is compiler-rt's, statically
///    linked and unnamed, and the shape recognizer identifies it by its four
///    immediates, not by name. So is a compiler-merged accessor (`…MaTm`),
///    whose body the evaluator then asks for through
///    ``instructions(ofFunctionAt:)`` and runs itself.
///
/// A call through a register goes the same way once the register's value
/// is known: a GOT slot that *binds* to a name answers through
/// ``callee(boundInSlotAt:)`` (the standalone case — the file holds no
/// address for the callee), a slot that rebases to an address in another
/// cache image answers through ``callee(at:)`` with that address, which
/// falls to the foreign-image lookup when it lies outside this image.
///
/// A metadata accessor's argument slots come from its descriptor's generic
/// context, in the order IRGen's `enumerateGenericSignatureRequirements`
/// emits and the runtime's generic-argument layout stores: shape classes,
/// then every key type parameter, then every key witness table.
package final class MachOThunkEnvironment: ThunkEvaluationEnvironment, MachOThunkEnvironmentLogging {
    /// Where an accessor the evaluator met lives, for the node builder.
    package struct AccessorOrigin {
        package let machO: MachOFile
        package let descriptorOffset: Int
    }

    package let machO: MachOFile
    package let addressSpace: ImageAddressSpace
    private let accessorIndex: MetadataAccessorIndex
    private let searchPathsOverride: [DependencySearchPath]?
    /// The file's pointer slots and trampolines, read through the shared
    /// resolvers (`CodeAddressResolution`, which the cross-reference analysis
    /// reads files through as well).
    private let slots: SlotResolver
    private let stubs: StubChainResolver
    private lazy var cacheImages: CacheImageLocator? = Self.cacheImageLocator(cacheOf: machO)
    private lazy var dependencyImages: DependencyImageResolver = DependencyImageResolver.resolver(for: machO)
    private var calleesByAddress: [UInt64: ThunkCallee] = [:]
    private var calleesBySlotAddress: [UInt64: ThunkCallee] = [:]
    private var instructionsByFunctionAddress: [UInt64: [ThunkInstruction]?] = [:]
    /// Keyed by the address a callee was met at: a `bl`'s target, or — for
    /// a callee reached through a GOT bind — the slot's address, which lies
    /// in a data segment and cannot collide with code.
    package private(set) var accessorOriginsByAddress: [UInt64: AccessorOrigin] = [:]
    /// Bind names no search path could place, in the order they were met.
    package private(set) var unlocatedBindNames: [String] = []

    /// `searchPaths` says where the images this file's binds name may be
    /// found; `nil` means ``defaultSearchPaths(for:)``.
    package init(machO: MachOFile, searchPaths: [DependencySearchPath]? = nil) {
        self.machO = machO
        let addressSpace = ImageAddressSpace(of: machO)
        self.addressSpace = addressSpace
        self.slots = SlotResolver(machO: machO, addressSpace: addressSpace)
        self.stubs = StubChainResolver(machO: machO, addressSpace: addressSpace)
        self.accessorIndex = MetadataAccessorIndex.index(for: machO)
        self.searchPathsOverride = searchPaths
    }

    /// The search paths in force: the caller's, else what the file's own
    /// location on disk implies followed by the host's shared cache.
    package private(set) lazy var searchPaths: [DependencySearchPath] = searchPathsOverride ?? Self.defaultSearchPaths(for: machO)

    /// What is looked through when a caller names no search paths: the
    /// caches or system root the file's location implies (an older
    /// simulator runtime's `RuntimeRoot`, a runtime's `dyld_sim_shared_cache`),
    /// then the running system's cache — which is where a macOS third-party
    /// app's dependencies live.
    package static func defaultSearchPaths(for machO: MachOFile) -> [DependencySearchPath] {
        DependencySearchPath.inferred(forRoot: machO) + [.systemDyldSharedCache]
    }

    /// The runtime entry points a type-construction thunk calls, by the
    /// symbol name a bind or an export trie spells them with.
    private static let runtimeEntryPointsByName: [String: ThunkCallee] = [
        "_swift_getWitnessTable": .witnessTableLookup,
        "_swift_checkMetadataState": .metadataStateCheck,
        "___swift_instantiateConcreteTypeFromMangledNameV2": .mangledNameInstantiation,
        "___swift_instantiateConcreteTypeFromMangledName": .mangledNameInstantiation,
        "___swift_instantiateConcreteTypeFromMangledNameAbstract": .mangledNameInstantiation,
        "___isPlatformVersionAtLeast": .availabilityCheck,
    ]

    /// The image's own symbols among ``namedRuntimeSymbols``, by address —
    /// from the raw symbol table, because the Swift symbol index deliberately
    /// carries no C symbol, and the compiler's per-image copy of
    /// `__swift_instantiateConcreteTypeFromMangledName` is exactly that (a
    /// local symbol, present while the image is unstripped).
    ///
    /// Read once per image and shared by every environment of it:
    /// `AccessorThunkReader.read` makes a new environment for each thunk, and
    /// reading walks the whole symbol table. Read per environment, SwiftUI's
    /// table was walked again for every opaque-type thunk its conformances
    /// name — about a sixth of reading its interface offline.
    private lazy var ownRuntimeSymbolNamesByAddress: [UInt64: String] =
        Self.ownRuntimeSymbolNamesCache.storage(in: machO) { machO in
            Self.ownRuntimeSymbolNamesByAddress(in: machO)
        } ?? [:]

    private static let ownRuntimeSymbolNamesCache = SharedCache<[UInt64: String]>(evictionGroup: .thunkResolution)

    private static func ownRuntimeSymbolNamesByAddress(in machO: MachOFile) -> [UInt64: String] {
        let addressSpace = ImageAddressSpace(of: machO)
        var namesByAddress: [UInt64: String] = [:]
        let wanted = Set(namedRuntimeSymbols)
        // A symbol table entry's value is already the address the thunk's
        // instructions name. Debug-map entries share the names and are skipped.
        if let symbols = machO.symbols64 {
            for symbol in symbols where wanted.contains(symbol.name) && !symbol.nlist.isDebuggingEntry {
                if let address = addressSpace.address(forSymbolValue: symbol.offset) { namesByAddress[address] = symbol.name }
            }
        } else if let symbols = machO.symbols32 {
            for symbol in symbols where wanted.contains(symbol.name) && !symbol.nlist.isDebuggingEntry {
                if let address = addressSpace.address(forSymbolValue: symbol.offset) { namesByAddress[address] = symbol.name }
            }
        }
        return namesByAddress
    }

    /// The locator for the cache `machO` was read from, one per image and
    /// shared by every environment of it; `nil` for a file not read out of a
    /// cache. `AccessorThunkReader.read` makes a new environment for each
    /// thunk, and a locator per environment read the paths of all the
    /// cache's images and opened the target image again for every thunk.
    private static func cacheImageLocator(cacheOf machO: MachOFile) -> CacheImageLocator? {
        guard machO.isLoadedFromDyldCache else { return nil }
        return cacheImageLocators.storage(in: machO) { machO in CacheImageLocator(cacheOf: machO) }
    }

    private static let cacheImageLocators = SharedCache<CacheImageLocator>(evictionGroup: .thunkResolution)

    // MARK: - ThunkEvaluationEnvironment

    package func callee(at address: UInt64) -> ThunkCallee {
        if let known = calleesByAddress[address] { return known }
        let callee = resolveCallee(at: address, islandHops: 0)
        calleesByAddress[address] = callee
        return callee
    }

    package func callee(boundInSlotAt slotAddress: UInt64) -> ThunkCallee {
        if let known = calleesBySlotAddress[slotAddress] { return known }
        let callee = resolveBoundCallee(inSlotAt: slotAddress)
        calleesBySlotAddress[slotAddress] = callee
        return callee
    }

    /// How many bytes to read before decoding a followed function — the
    /// reader's window, for the same reason: the decoder's instruction cap
    /// is the real bound.
    private static let functionWindowSize = 1024

    package func instructions(ofFunctionAt address: UInt64) -> [ThunkInstruction]? {
        if let known = instructionsByFunctionAddress[address] { return known }
        let decoded = decodeFunction(at: address)
        instructionsByFunctionAddress[address] = decoded
        return decoded
    }

    /// The function at `address` decoded the way the reader decodes the
    /// thunk itself, when the address is in this image's `__TEXT`.
    private func decodeFunction(at address: UInt64) -> [ThunkInstruction]? {
        guard addressSpace.isInTextSegment(address),
              let offset = addressSpace.offset(forAddress: address),
              let bytes: [UInt8] = try? machO.readElements(offset: offset, numberOfElements: Self.functionWindowSize)
        else { return nil }
        return try? CapstoneThunkDecoder.decodeFunction(
            machineCode: Data(bytes),
            startAddress: address,
            maximumInstructionCount: CapstoneThunkDecoder.constructionMaximumInstructionCount,
            isKnownFunction: { [self] target in
                if case .unknown = callee(at: target) { return false }
                return true
            }
        )
    }

    package func pointer(at address: UInt64) -> UInt64? {
        slots.rebaseTarget(ofSlotAt: address)
    }

    package func slotSymbolName(at address: UInt64) -> String? {
        switch slots.content(ofSlotAt: address) {
        case .boundSymbol(let bindName)?:
            return bindName
        case .address(let targetAddress)?:
            return symbolName(atAddress: targetAddress)
        case nil:
            return nil
        }
    }

    /// The name of the symbol at `address` — in this image through its
    /// symbol index, in another cache image through its export trie (the
    /// runtime's entry points and capability flags are exported).
    private func symbolName(atAddress address: UInt64) -> String? {
        if let ownName = ownRuntimeSymbolNamesByAddress[address] { return ownName }
        guard let cacheImages, let foreignImage = cacheImages.image(containing: address) else { return nil }
        return cacheImages.exportedName(atAddress: address, in: foreignImage, among: Self.namedRuntimeSymbols)
    }

    /// The runtime symbols this analysis recognizes by name: entry points a
    /// thunk calls, and the capability flag it tests.
    private static let namedRuntimeSymbols: [String] = Array(runtimeEntryPointsByName.keys) + Array(ThunkTypeEvaluator.runtimeCapabilityFlagNames)

    // MARK: - Resolution

    private func resolveCallee(at address: UInt64, islandHops: Int) -> ThunkCallee {
        if addressSpace.containsAddress(address), let offset = addressSpace.offset(forAddress: address) {
            if let descriptorOffset = accessorIndex.descriptorOffset(forAccessorOffset: offset) {
                return metadataAccessor(at: address, descriptorOffset: descriptorOffset, in: machO)
            }
            // A runtime helper the compiler emits into the image itself
            // (`__swift_instantiateConcreteTypeFromMangledNameV2` is one) carries
            // a local symbol in an unstripped image.
            if let ownName = ownRuntimeSymbolNamesByAddress[address], let runtimeEntryPoint = Self.runtimeEntryPoint(named: ownName) {
                return runtimeEntryPoint
            }
            if let symbolName = concreteTypeAccessorSymbolName(atOffset: offset) {
                return .concreteTypeAccessor(symbolName: symbolName)
            }
        } else {
            // An address outside this image's segments: another image's
            // function reached through a rebased pointer, or a trampoline on
            // the way to one. The segment test is deliberate — a cache
            // image's offset conversion answers for the whole cache (see
            // `ImageAddressSpace.containsAddress`).
            let foreign = foreignCallee(at: address, targetAddress: address)
            if case .unknown = foreign {} else { return foreign }
        }
        // A trampoline, wherever it sits — inside the image's `__stubs`, or
        // between images in a device cache, whose stubs and islands live in
        // regions no image's segments cover. A GOT-loading stub names a
        // slot; an island computes its target. Either way the target is
        // classified again, up to a fixed number of hops.
        guard islandHops < StubChainResolver.maximumHops else { return .unknown }
        switch stubs.hop(at: address) {
        case .slotLoad(_, let slotAddress)?:
            switch slots.content(ofSlotAt: slotAddress) {
            case .boundSymbol(let bindName)?:
                if let runtimeEntryPoint = Self.runtimeEntryPoint(named: bindName) { return runtimeEntryPoint }
                return dependencyCallee(at: address, bindName: bindName)
            case .address(let targetAddress)?:
                return hopping(from: address, to: targetAddress, islandHops: islandHops)
            case nil:
                return .unknown
            }
        case .island(_, let target)?:
            return hopping(from: address, to: target, islandHops: islandHops)
        case .registerSettingStub?, nil:
            // A cache-shared selector stub sends a message; no thunk calls one.
            return .unknown
        }
    }

    /// What a GOT slot that binds by name refers to: a runtime entry point,
    /// or another image's accessor located through the search paths.
    private func resolveBoundCallee(inSlotAt slotAddress: UInt64) -> ThunkCallee {
        guard let bindName = slots.boundSymbolName(ofSlotAt: slotAddress) else { return .unknown }
        if let runtimeEntryPoint = Self.runtimeEntryPoint(named: bindName) { return runtimeEntryPoint }
        return dependencyCallee(at: slotAddress, bindName: bindName)
    }

    /// Classifies a trampoline's target, and files an accessor found that
    /// way under the address the thunk called — the stub or island — so the
    /// node builder finds it where the expression names it.
    private func hopping(from trampolineAddress: UInt64, to target: UInt64, islandHops: Int) -> ThunkCallee {
        let callee = resolveCallee(at: target, islandHops: islandHops + 1)
        if case .metadataAccessor(_, let argumentSlots) = callee, let origin = accessorOriginsByAddress[target] {
            accessorOriginsByAddress[trampolineAddress] = origin
            return .metadataAccessor(address: trampolineAddress, argumentSlots: argumentSlots)
        }
        return callee
    }

    /// The symbol at `offset` when it is a lazily specialized metadata
    /// accessor: `type metadata accessor for <a bound generic type>`, with
    /// nothing left unbound in the type — see ``isConcreteTypeAccessorSymbol(_:)``.
    private func concreteTypeAccessorSymbolName(atOffset offset: Int) -> String? {
        guard let symbols = machO.symbols(offset: offset) else { return nil }
        for symbol in symbols {
            guard let symbolNode = try? SymbolicDemangler.demangleSymbol(for: symbol, in: machO) ?? nil,
                  Self.isConcreteTypeAccessorSymbol(symbolNode)
            else { continue }
            return symbol.name
        }
        return nil
    }

    /// Whether a demangled symbol names a lazily specialized metadata
    /// accessor whose name IS the answer.
    ///
    /// Three refusals, each of which would otherwise print a real, wrong
    /// type. **Unbound** (`type metadata accessor for Mutex`): a
    /// descriptor's own accessor, whose arguments come from the call, is the
    /// accessor index's business — one this image does not own never carries
    /// a local symbol — so only a name spelling every argument (a
    /// `boundGeneric…` node) is taken. **Merged** (`merged type metadata
    /// accessor for Any?`, `…MaTm`): the compiler folded several accessor
    /// bodies into one and the symbol keeps the name of *one* of them, while
    /// the callee it actually reaches arrives as a function-pointer argument
    /// — SwiftUICore's `PlatformAccessibilitySettingsDefinition.cache`
    /// printed `Array<LayoutDirection>` for a `Mutex<Storage>` the moment
    /// this predicate forgot to look for the `mergedFunction` node. And a
    /// type still mentioning a **generic parameter** is not concrete.
    package static func isConcreteTypeAccessorSymbol(_ symbolNode: Node) -> Bool {
        guard !symbolNode.contains(Node.Kind.mergedFunction),
              let accessorNode = symbolNode.first(of: Node.Kind.typeMetadataAccessFunction),
              let typeNode = accessorNode.firstChild
        else { return false }
        return boundGenericKinds.contains(where: { typeNode.contains($0) })
            && !typeNode.contains(Node.Kind.dependentGenericParamType)
    }

    private static let boundGenericKinds: [Node.Kind] = [
        .boundGenericStructure, .boundGenericEnum, .boundGenericClass, .boundGenericOtherNominalType, .boundGenericTypeAlias,
    ]

    /// A bind to another image: the image exporting `bindName` among the
    /// root's located dependencies, and that image's accessor index for the
    /// descriptor. A name no image exports is remembered for the reader's
    /// limitations — the missing image is the fact worth reporting.
    private func dependencyCallee(at address: UInt64, bindName: String) -> ThunkCallee {
        guard let location = dependencyImages.location(ofExportedSymbol: bindName, searchPaths: searchPaths) else {
            if !unlocatedBindNames.contains(bindName) { unlocatedBindNames.append(bindName) }
            #log(.info, "no search path located an image exporting \(bindName, privacy: .public)")
            return .unknown
        }
        let image = location.image
        let imageAddressSpace = ImageAddressSpace(of: image)
        guard let exportedAddress = imageAddressSpace.address(forExportedSymbolOffset: location.exportedSymbolOffset),
              let exportedOffset = imageAddressSpace.offset(forAddress: exportedAddress)
        else { return .unknown }
        if let descriptorOffset = MetadataAccessorIndex.index(for: image).descriptorOffset(forAccessorOffset: exportedOffset) {
            return metadataAccessor(at: address, descriptorOffset: descriptorOffset, in: image)
        }
        #log(.info, "\(bindName, privacy: .public) is exported by \(image.imagePath, privacy: .public) but is not one of its metadata accessors")
        return .unknown
    }

    private func foreignCallee(at address: UInt64, targetAddress: UInt64) -> ThunkCallee {
        guard let cacheImages, let foreignImage = cacheImages.image(containing: targetAddress) else { return .unknown }
        let foreignAddressSpace = ImageAddressSpace(of: foreignImage)
        guard let foreignOffset = foreignAddressSpace.offset(forAddress: targetAddress) else { return .unknown }
        if let descriptorOffset = MetadataAccessorIndex.index(for: foreignImage).descriptorOffset(forAccessorOffset: foreignOffset) {
            return metadataAccessor(at: address, descriptorOffset: descriptorOffset, in: foreignImage)
        }
        if let name = cacheImages.exportedName(atAddress: targetAddress, in: foreignImage, among: Self.namedRuntimeSymbols) {
            return Self.runtimeEntryPointsByName[name] ?? .unknown
        }
        return .unknown
    }

    private static func runtimeEntryPoint(named name: String) -> ThunkCallee? {
        if let callee = runtimeEntryPointsByName[name] { return callee }
        // A bind may spell the name without the leading underscore.
        return runtimeEntryPointsByName["_" + name]
    }

    private func metadataAccessor(at address: UInt64, descriptorOffset: Int, in image: MachOFile) -> ThunkCallee {
        guard let argumentSlots = accessorArgumentSlots(ofDescriptorAt: descriptorOffset, in: image) else { return .unknown }
        accessorOriginsByAddress[address] = AccessorOrigin(machO: image, descriptorOffset: descriptorOffset)
        return .metadataAccessor(address: address, argumentSlots: argumentSlots)
    }

    /// The accessor's key arguments, in generic-argument-layout order.
    private func accessorArgumentSlots(ofDescriptorAt descriptorOffset: Int, in image: MachOFile) -> [ThunkArgumentSlot]? {
        do {
            let descriptor: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(at: descriptorOffset, in: image.context)
            guard let genericContext = try descriptor.genericContext(in: image.context) else { return [] }
            var slots: [ThunkArgumentSlot] = []
            slots.append(contentsOf: repeatElement(.other, count: genericContext.typePacks.count))
            for parameter in genericContext.parameters where parameter.hasKeyArgument {
                slots.append(parameter.kind == .type ? .type : .other)
            }
            for requirement in genericContext.requirements where requirement.flags.contains(.hasKeyArgument) {
                slots.append(.witnessTable)
            }
            return slots
        } catch {
            #log(.info, "could not read the generic context of the descriptor at \(descriptorOffset, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
