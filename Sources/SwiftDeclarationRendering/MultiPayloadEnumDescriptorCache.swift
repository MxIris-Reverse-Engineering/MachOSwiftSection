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
            multiPayloadEnumDescriptorByNode = Self.indexDescriptors(try machO.swift.multiPayloadEnumDescriptors, in: machO)
        } catch {
            // The section read itself failed, so there is no descriptor list to
            // index at all. stderr, never stdout: `swift-section interface` /
            // `dump` stream the generated Swift to stdout, so a diagnostic
            // printed there lands inside the generated output (issue #102).
            FileHandle.standardError.write(Data("MultiPayloadEnumDescriptorCache: \(error)\n".utf8))
        }

        let storage = Storage()
        storage.multiPayloadEnumDescriptorByNode = multiPayloadEnumDescriptorByNode
        return storage
    }

    /// Indexes a `__swift5_mpenum` descriptor sequence into the node-keyed map.
    ///
    /// Separated from `buildStorage` so the per-descriptor error contract is
    /// unit-testable: a deliberately unreadable descriptor can be spliced into
    /// the sequence, which the section-backed property cannot express.
    static func indexDescriptors<MachO: MachOSwiftSectionRepresentableWithCache>(
        _ multiPayloadEnumDescriptors: some Sequence<MultiPayloadEnumDescriptor>,
        in machO: MachO
    ) -> [Node: MultiPayloadEnumDescriptor] {
        var multiPayloadEnumDescriptorByNode: [Node: MultiPayloadEnumDescriptor] = [:]
        for multiPayloadEnumDescriptor in multiPayloadEnumDescriptors {
            // Caught PER DESCRIPTOR, not around the loop: a loop-level catch
            // exits on the first bad record, so every descriptor after it is
            // missing from the published map and its enum silently falls back to
            // `calculateTaggedMultiPayload` — a WRONG layout, not a missing one,
            // and memoized for the image's lifetime by the enclosing
            // `SharedCache`.
            do {
                let mangledTypeName = try multiPayloadEnumDescriptor.mangledTypeName(in: machO)

                let node = try MetadataReader.demangleType(for: mangledTypeName, in: machO)

                multiPayloadEnumDescriptorByNode[node] = multiPayloadEnumDescriptor
            } catch {
                // stderr, never stdout (issue #102).
                FileHandle.standardError.write(Data("MultiPayloadEnumDescriptorCache: skipped one descriptor: \(error)\n".utf8))
                continue
            }
        }
        return multiPayloadEnumDescriptorByNode
    }

    func multiPayloadEnumDescriptor(for node: Node, in machO: some MachOSwiftSectionRepresentableWithCache) -> MultiPayloadEnumDescriptor? {
        let storage = storage(in: machO)
        return storage?.multiPayloadEnumDescriptorByNode[node]
    }
}
