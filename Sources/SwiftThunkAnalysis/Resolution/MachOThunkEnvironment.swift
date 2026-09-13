import Foundation
import FoundationToolbox
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection

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
///    load names a GOT slot. The slot is either a **bind** — a symbol name,
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
///    immediates, not by name.
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
    package let addressSpace: ThunkAddressSpace
    private let accessorIndex: MetadataAccessorIndex
    private let searchPathsOverride: [DependencySearchPath]?
    private lazy var cacheImages: CacheImageResolver? = CacheImageResolver(cacheOf: machO)
    private lazy var dependencyImages: DependencyImageResolver = DependencyImageResolver.resolver(for: machO)
    private var calleesByAddress: [UInt64: ThunkCallee] = [:]
    package private(set) var accessorOriginsByAddress: [UInt64: AccessorOrigin] = [:]
    /// Bind names no search path could place, in the order they were met.
    package private(set) var unlocatedBindNames: [String] = []

    /// `searchPaths` says where the images this file's binds name may be
    /// found; `nil` means ``defaultSearchPaths(for:)``.
    package init(machO: MachOFile, searchPaths: [DependencySearchPath]? = nil) {
        self.machO = machO
        self.addressSpace = ThunkAddressSpace(of: machO)
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
    private lazy var ownRuntimeSymbolNamesByAddress: [UInt64: String] = {
        var namesByAddress: [UInt64: String] = [:]
        let wanted = Set(Self.namedRuntimeSymbols)
        // `Symbol.offset` is a file offset; the segment table turns it into
        // the address the thunk's instructions name.
        if let symbols = machO.symbols64 {
            for symbol in symbols where wanted.contains(symbol.name) {
                if let address = addressSpace.address(forFileOffset: symbol.offset) { namesByAddress[address] = symbol.name }
            }
        } else if let symbols = machO.symbols32 {
            for symbol in symbols where wanted.contains(symbol.name) {
                if let address = addressSpace.address(forFileOffset: symbol.offset) { namesByAddress[address] = symbol.name }
            }
        }
        return namesByAddress
    }()

    // MARK: - ThunkEvaluationEnvironment

    package func callee(at address: UInt64) -> ThunkCallee {
        if let known = calleesByAddress[address] { return known }
        let callee = resolveCallee(at: address)
        calleesByAddress[address] = callee
        return callee
    }

    package func pointer(at address: UInt64) -> UInt64? {
        guard let offset = addressSpace.offset(forAddress: address),
              let target = machO.resolveRebase(fileOffset: offset)
        else { return nil }
        return rebaseTargetAddress(target)
    }

    package func slotSymbolName(at address: UInt64) -> String? {
        guard let offset = addressSpace.offset(forAddress: address) else { return nil }
        if let bindName = machO.resolveBind(fileOffset: offset) { return bindName }
        guard let target = machO.resolveRebase(fileOffset: offset),
              let targetAddress = rebaseTargetAddress(target)
        else { return nil }
        return symbolName(atAddress: targetAddress)
    }

    /// `MachOKitExtensions.resolveRebase(fileOffset:)` answers in two
    /// accountings: for a cache image the target minus `sharedRegionStart`
    /// (this module's offset), for a standalone file the target's own
    /// address.
    private func rebaseTargetAddress(_ target: UInt64) -> UInt64? {
        machO.cache != nil ? addressSpace.address(forOffset: Int(target)) : target
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

    private func resolveCallee(at address: UInt64) -> ThunkCallee {
        guard let offset = addressSpace.offset(forAddress: address) else { return .unknown }
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
        guard let slotAddress = stubSlotAddress(at: address),
              let slotOffset = addressSpace.offset(forAddress: slotAddress)
        else { return .unknown }
        if let bindName = machO.resolveBind(fileOffset: slotOffset) {
            if let runtimeEntryPoint = Self.runtimeEntryPoint(named: bindName) { return runtimeEntryPoint }
            return dependencyCallee(at: address, bindName: bindName)
        }
        guard let target = machO.resolveRebase(fileOffset: slotOffset),
              let targetAddress = rebaseTargetAddress(target),
              let targetOffset = addressSpace.offset(forAddress: targetAddress)
        else { return .unknown }
        if let descriptorOffset = accessorIndex.descriptorOffset(forAccessorOffset: targetOffset) {
            return metadataAccessor(at: address, descriptorOffset: descriptorOffset, in: machO)
        }
        if let ownName = ownRuntimeSymbolNamesByAddress[targetAddress], let runtimeEntryPoint = Self.runtimeEntryPoint(named: ownName) {
            return runtimeEntryPoint
        }
        if let symbolName = concreteTypeAccessorSymbolName(atOffset: targetOffset) {
            return .concreteTypeAccessor(symbolName: symbolName)
        }
        return foreignCallee(at: address, targetAddress: targetAddress)
    }

    /// The GOT slot a stub at `address` loads its target from.
    private func stubSlotAddress(at address: UInt64) -> UInt64? {
        guard let offset = addressSpace.offset(forAddress: address),
              let bytes: [UInt8] = try? machO.readElements(offset: offset, numberOfElements: 16),
              let instructions = try? CapstoneThunkDecoder.decode(machineCode: Data(bytes), startAddress: address, maximumInstructionCount: 4)
        else { return nil }
        var tracker = ThunkRegisterTracker()
        for instruction in instructions {
            switch instruction.operation {
            case .loadFromMemory(_, let base, let displacement):
                guard let baseAddress = tracker.address(of: base) else { return nil }
                return baseAddress &+ UInt64(bitPattern: displacement)
            case .indirectBranch, .returnFromFunction, .call, .branch:
                return nil
            default:
                tracker.apply(instruction.operation)
            }
        }
        return nil
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
        let imageAddressSpace = ThunkAddressSpace(of: image)
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
        let foreignAddressSpace = ThunkAddressSpace(of: foreignImage)
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
            let descriptor: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(from: descriptorOffset, in: image)
            guard let genericContext = try descriptor.genericContext(in: image) else { return [] }
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

/// Finds, inside a dyld shared cache, the image an address belongs to.
///
/// The main cache header lists every image with its load address; the image
/// whose address is the greatest one not above the target is the one that
/// contains it (`__TEXT` segments are laid out contiguously in address
/// order). Images are opened on first use and kept, because one thunk
/// typically calls into the same two images (`SwiftUICore`, `libswiftCore`)
/// many times.
package final class CacheImageResolver {
    private let cache: DyldCache
    private let imagesByAddress: [(address: UInt64, path: String)]
    private var openedImagesByPath: [String: MachOFile?] = [:]
    private var entryPointAddressesByImagePath: [String: [UInt64: String]] = [:]

    package init?(cacheOf machO: MachOFile) {
        guard let cache = machO.cache else { return nil }
        let mainCache = cache.mainCache ?? cache
        guard let imageInfos = mainCache.imageInfos else { return nil }
        var images: [(address: UInt64, path: String)] = []
        for imageInfo in imageInfos {
            guard let path = imageInfo.path(in: mainCache) else { continue }
            images.append((address: UInt64(imageInfo.layout.address), path: path))
        }
        guard !images.isEmpty else { return nil }
        self.cache = cache
        self.imagesByAddress = images.sorted { $0.address < $1.address }
    }

    package func image(containing address: UInt64) -> MachOFile? {
        // Greatest load address not above the target.
        var low = 0
        var high = imagesByAddress.count
        while low < high {
            let middle = (low + high) / 2
            if imagesByAddress[middle].address <= address { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let path = imagesByAddress[low - 1].path
        if let opened = openedImagesByPath[path] { return opened }
        let opened = cache.machOFile(by: .path(path))
        openedImagesByPath[path] = opened
        return opened
    }

    /// Which of `names` — runtime symbols, by their exported spelling — the
    /// address in `image` is, if any.
    ///
    /// The export trie's offsets are header-relative
    /// (``ThunkAddressSpace/address(forExportedSymbolOffset:)``). Until the
    /// standalone-file batch this went through the file-offset conversion,
    /// which for a cache image lands in `__LINKEDIT`, so the table held
    /// wrong addresses and never matched; the cache readings survived only
    /// because a witness-table call's result is skipped by the name and a
    /// capability flag's unnamed pointer still reads as non-zero.
    package func exportedName(atAddress address: UInt64, in image: MachOFile, among names: some Sequence<String>) -> String? {
        let path = image.imagePath
        if entryPointAddressesByImagePath[path] == nil {
            var addressesByName: [UInt64: String] = [:]
            let addressSpace = ThunkAddressSpace(of: image)
            for name in names {
                guard let exported = image.exportTrie?.search(by: name),
                      let exportedSymbolOffset = exported.offset,
                      let exportedAddress = addressSpace.address(forExportedSymbolOffset: exportedSymbolOffset)
                else { continue }
                addressesByName[exportedAddress] = name
            }
            entryPointAddressesByImagePath[path] = addressesByName
        }
        return entryPointAddressesByImagePath[path]?[address]
    }
}
