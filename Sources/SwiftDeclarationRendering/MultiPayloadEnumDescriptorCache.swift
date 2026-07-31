import Foundation
import MachOKit
import MachOSwiftSection
import Demangling
import FoundationToolbox
@_spi(Internals) import MachOCaches
@_spi(Internals) import SwiftInspection

/// Per-image index of `__swift5_mpenum` descriptors keyed by their demangled
/// type node.
///
/// Restored from the pre-leaf-migration `EnumDumper` cache (removed in
/// `ebb04d3`, which replaced it with a per-enum linear rescan inside
/// `RuntimeFieldLayoutBackend`). The cache carries two properties the rescan
/// lost:
///
/// - **Error tolerance**: the build loop publishes a *partial* map — one
///   undemanglable descriptor only makes its own enum miss the lookup (the
///   caller then falls back to the tagged-projection layout), instead of a
///   thrown error suppressing every multi-payload enum's layout comments.
/// - **Linearity**: the section is scanned and demangled once per image, not
///   once per rendered enum.
final class MultiPayloadEnumDescriptorCache: SharedCache<MultiPayloadEnumDescriptorCache.Storage>, @unchecked Sendable {
    static let shared = MultiPayloadEnumDescriptorCache()

    private override init() {
        super.init()
    }

    final class Storage {
        @Mutex
        var multiPayloadEnumDescriptorByNode: [Node: MultiPayloadEnumDescriptor] = [:]
    }

    override func buildStorage(for machO: some MachORepresentableWithCache) -> Storage? {
        guard let machO = machO as? (any MachOSwiftSectionRepresentableWithCache) else { return nil }
        var multiPayloadEnumDescriptorByNode: [Node: MultiPayloadEnumDescriptor] = [:]

        do {
            for multiPayloadEnumDescriptor in try machO.swift.multiPayloadEnumDescriptors {
                let mangledTypeName = try multiPayloadEnumDescriptor.mangledTypeName(in: machO)

                let node = try MetadataReader.demangleType(for: mangledTypeName, in: machO)

                multiPayloadEnumDescriptorByNode[node] = multiPayloadEnumDescriptor
            }
        } catch {
            print(error)
        }

        let storage = Storage()
        storage.multiPayloadEnumDescriptorByNode = multiPayloadEnumDescriptorByNode
        return storage
    }

    func multiPayloadEnumDescriptor(for node: Node, in machO: some MachOSwiftSectionRepresentableWithCache) -> MultiPayloadEnumDescriptor? {
        let storage = storage(in: machO)
        return storage?.multiPayloadEnumDescriptorByNode[node]
    }
}
