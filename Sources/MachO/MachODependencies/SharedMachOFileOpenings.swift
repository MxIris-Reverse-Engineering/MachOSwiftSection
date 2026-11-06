import Foundation
import MachOKit
import MachOKitExtensions

/// One opening of each Mach-O file that dependency locators read by path — an
/// explicit `.machOFile(path:)` search path, or a file under a system root —
/// shared by every locator for as long as anything still holds it.
///
/// A locator reads every explicit file it is given when it is built, and each
/// consumer of a dependency closure builds one per root, so RuntimeViewer
/// reading a bundle opened each of the bundle's Mach-O files again for every
/// image of the bundle and every consumer.
///
/// Held weakly and keyed by the file's identity (`DependencyFileIdentity`) and
/// the CPU whose slice is picked, as `SharedDyldCacheOpenings` keeps caches.
/// One standalone `MachOFile` is safe to share across threads from MachOKit
/// 0.55.101 on: before it, the file's `cache` and `fullCache` probed the file
/// as a dyld cache on every read and stored the failed result without a lock.
enum SharedMachOFileOpenings {
    /// The slice of the Mach-O file at `url` that `preferredSlice(among:preferredCPU:)`
    /// picks for `preferredCPU`, opened on the first request while no other
    /// opening of it is alive. `nil` when the file holds no Mach-O slice;
    /// throws what reading the file throws.
    static func machOFile(at url: URL, preferredCPU: CPU?) throws -> MachOFile? {
        try registry.machOFile(at: url, preferredCPU: preferredCPU)
    }

    /// For a fat file, the slice to read: the root binary's own architecture,
    /// so a universal dependency is laid out for the same target as the root.
    /// Matched on CPU type plus subtype, then on type alone, then the first
    /// slice.
    ///
    /// Compared on `CPU.type` and `CPU.subtype` rather than `CPU ==`: the
    /// struct's synthesized equality includes the raw subtype's capability
    /// bits (the arm64e pointer-authentication ABI version and versioned-ABI
    /// flag under `CPU_SUBTYPE_MASK`), so a versioned-ABI arm64e slice would
    /// compare unequal to a plain arm64e root and silently fall through to
    /// the type-only match — the arm64 / arm64e confusion this exists to
    /// avoid. `subtype` masks those bits.
    static func preferredSlice(among slices: [MachOFile], preferredCPU: CPU?) -> MachOFile? {
        guard let preferredCPU else { return slices.first }
        if let exactSlice = slices.first(where: { $0.header.cpu.type == preferredCPU.type && $0.header.cpu.subtype == preferredCPU.subtype }) {
            return exactSlice
        }
        if let sameTypeSlice = slices.first(where: { $0.header.cpu.type == preferredCPU.type }) {
            return sameTypeSlice
        }
        return slices.first
    }

    private static func openPreferredSlice(at url: URL, preferredCPU: CPU?) throws -> MachOFile? {
        preferredSlice(among: try File.loadFromFile(url: url).machOFiles, preferredCPU: preferredCPU)
    }

    /// Two CPUs that differ only in capability bits pick the same slice but
    /// get an opening each: less sharing, never a wrong slice.
    private struct Key: Hashable {
        let file: DependencyFileIdentity
        let preferredCPUTypeRawValue: cpu_type_t?
        let preferredCPUSubtypeRawValue: cpu_subtype_t?
    }

    private static let registry = Registry()

    private final class Registry: @unchecked Sendable {
        /// One per file and CPU, created under the registry's lock and filled
        /// in under its own, so a file being opened holds up only the requests
        /// for that file.
        private final class Slot: @unchecked Sendable {
            let lock = NSLock()
            weak var machOFile: MachOFile?
        }

        private let lock = NSLock()
        private var slotsByKey: [Key: Slot] = [:]

        func machOFile(at url: URL, preferredCPU: CPU?) throws -> MachOFile? {
            guard let fileIdentity = DependencyFileIdentity(fileAt: url) else {
                return try SharedMachOFileOpenings.openPreferredSlice(at: url, preferredCPU: preferredCPU)
            }
            let key = Key(
                file: fileIdentity,
                preferredCPUTypeRawValue: preferredCPU?.typeRawValue,
                preferredCPUSubtypeRawValue: preferredCPU?.subtypeRawValue
            )
            lock.lock()
            let slot: Slot
            if let existingSlot = slotsByKey[key] {
                slot = existingSlot
            } else {
                slot = Slot()
                slotsByKey[key] = slot
            }
            lock.unlock()

            slot.lock.lock()
            defer { slot.lock.unlock() }
            if let machOFile = slot.machOFile {
                return machOFile
            }
            guard let machOFile = try SharedMachOFileOpenings.openPreferredSlice(at: url, preferredCPU: preferredCPU) else {
                return nil
            }
            slot.machOFile = machOFile
            return machOFile
        }
    }
}
