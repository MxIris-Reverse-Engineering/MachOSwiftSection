import Foundation
import MachOKit
import MachOKitExtensions

/// What a pointer slot of a Mach-O file holds, decoded from the file's
/// fixups rather than read as it stands: in a file, a slot holds a chained
/// fixup or a cache-relative rebase, which dyld turns into an address only
/// when it loads the image.
///
/// One question for every kind of slot — a GOT or auth GOT slot, an
/// Objective-C selector, class, superclass or protocol reference, an ivar
/// offset variable: which kind a slot is, is the caller's to say. Shared by
/// the accessor-thunk reader and the cross-reference analysis (evolution
/// proposal `offline-cross-references-and-symbolication`).
package struct SlotResolver {
    /// What a slot holds.
    package enum Content: Hashable, Sendable {
        /// A rebase: the unslid address it points at.
        case address(UInt64)
        /// A bind: the name of the symbol it binds to, as the file spells it.
        case boundSymbol(String)
    }

    package let machO: MachOFile
    package let addressSpace: ImageAddressSpace

    package init(machO: MachOFile, addressSpace: ImageAddressSpace) {
        self.machO = machO
        self.addressSpace = addressSpace
    }

    package init(machO: MachOFile) {
        self.init(machO: machO, addressSpace: ImageAddressSpace(of: machO))
    }

    /// What the slot at the unslid `address` holds: a bind first — a
    /// standalone file's imports — then a rebase.
    package func content(ofSlotAt address: UInt64) -> Content? {
        guard let offset = addressSpace.offset(forAddress: address) else { return nil }
        if let bindName = machO.resolveBind(fileOffset: offset) { return .boundSymbol(bindName) }
        guard let target = rebaseTarget(ofSlotAtOffset: offset) else { return nil }
        return .address(target)
    }

    /// The name a slot at the unslid `address` binds to, when it is a bind.
    package func boundSymbolName(ofSlotAt address: UInt64) -> String? {
        guard let offset = addressSpace.offset(forAddress: address) else { return nil }
        return machO.resolveBind(fileOffset: offset)
    }

    /// The unslid address a slot at the unslid `address` rebases to, when it
    /// is a rebase.
    package func rebaseTarget(ofSlotAt address: UInt64) -> UInt64? {
        guard let offset = addressSpace.offset(forAddress: address) else { return nil }
        return rebaseTarget(ofSlotAtOffset: offset)
    }

    /// `MachOKitExtensions.resolveRebase(fileOffset:)` answers in two
    /// accountings: for a cache image the target minus `sharedRegionStart`
    /// (the offsets `MachOSwiftSection` uses), for a standalone file the
    /// target's offset from the image's preferred load address — what a
    /// chained fixup stores. That offset is the address only where `__TEXT`
    /// lies at 0, as a dylib's does; a main executable's lies at
    /// 0x100000000, and read as an address the target pointed 4 GiB low (the
    /// accessor-thunk reader took it so until the offline cross references
    /// read a whole app). A standalone file without chained fixups — rebased
    /// by opcodes, as older deployment targets are — is not
    /// decoded: MachOKitExtensions answers nothing for its slots.
    private func rebaseTarget(ofSlotAtOffset offset: Int) -> UInt64? {
        guard let target = machO.resolveRebase(fileOffset: offset) else { return nil }
        return machO.cache != nil ? addressSpace.address(forOffset: Int(target)) : addressSpace.address(forHeaderOffset: Int(target))
    }
}
