import Foundation
import FoundationToolbox
import MachOKit
import MachOFoundation
import MachOSwiftSection

@Loggable(.fileprivate, subsystem: "com.machoswiftsection.swift-thunk-analysis", category: "MachOThunkEnvironment")
fileprivate protocol MachOThunkEnvironmentLogging {}

/// The evaluator's view of one Mach-O: what each call target is, and what a
/// pointer-sized word holds.
///
/// ## Naming a call target
///
/// A thunk's calls go one of three ways, and the order below is the order
/// they are tried:
///
/// 1. **A metadata accessor in this image** — `MetadataAccessorIndex` maps
///    the address to the descriptor whose accessor it is.
/// 2. **A stub.** Inside a shared cache every cross-image call goes through
///    a four-instruction stub (`adrp x17` / `add x17` / `ldr x16, [x17]` /
///    `braa x16, x17`; a standalone binary's is `adrp` / `ldr` / `br`) whose
///    load names a GOT slot. The slot is either a **bind** — a symbol name,
///    the standalone case — or, inside a cache where dyld already resolved
///    every bind, a **rebase** to the callee's address in some other image.
///    A bound name is classified directly (`_swift_getWitnessTable`,
///    `___swift_instantiateConcreteTypeFromMangledNameV2`); a rebase target
///    is located through the cache's image table, and the image it lands in
///    answers through its own accessor index or its export trie.
/// 3. Anything else is ``ThunkCallee/unknown``. The availability check is
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
    private lazy var cacheImages: CacheImageResolver? = CacheImageResolver(cacheOf: machO)
    private var calleesByAddress: [UInt64: ThunkCallee] = [:]
    package private(set) var accessorOriginsByAddress: [UInt64: AccessorOrigin] = [:]

    package init(machO: MachOFile) {
        self.machO = machO
        self.addressSpace = ThunkAddressSpace(of: machO)
        self.accessorIndex = MetadataAccessorIndex.index(for: machO)
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
        guard let slotAddress = stubSlotAddress(at: address),
              let slotOffset = addressSpace.offset(forAddress: slotAddress)
        else { return .unknown }
        if let bindName = machO.resolveBind(fileOffset: slotOffset) {
            return Self.runtimeEntryPoint(named: bindName) ?? .unknown
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
    package func exportedName(atAddress address: UInt64, in image: MachOFile, among names: some Sequence<String>) -> String? {
        let path = image.imagePath
        if entryPointAddressesByImagePath[path] == nil {
            var addressesByName: [UInt64: String] = [:]
            let addressSpace = ThunkAddressSpace(of: image)
            for name in names {
                guard let exported = image.exportTrie?.search(by: name),
                      let fileOffset = exported.offset,
                      let exportedAddress = addressSpace.address(forFileOffset: fileOffset)
                else { continue }
                addressesByName[exportedAddress] = name
            }
            entryPointAddressesByImagePath[path] = addressesByName
        }
        return entryPointAddressesByImagePath[path]?[address]
    }
}
