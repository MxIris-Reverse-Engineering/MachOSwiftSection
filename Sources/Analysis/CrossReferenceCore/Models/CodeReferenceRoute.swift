/// How the code reached what it references: the instructions and the
/// trampolines on the way, not what the target is. A reference through a
/// stub island is as much a call as a direct one; the route is what a
/// reader checks before trusting it, or follows to see it for itself.
public enum CodeReferenceRoute: UInt8, Hashable, Sendable, CaseIterable {
    /// A `bl` or `b` straight to the target.
    case direct
    /// A stub in the referencing image's own stub sections — `__stubs`,
    /// `__auth_stubs`, `__objc_stubs`.
    case imageStub
    /// One or more stub islands a dyld shared cache places between its
    /// images, when a `bl` cannot reach across its subcaches.
    case stubIsland
    /// A stub the whole cache shares: macOS / iOS 27's selector stubs and
    /// GOT stubs outside every image.
    case cacheSharedStub
    /// An `adrp` / `ldr` through a pointer slot — a GOT or auth GOT slot, a
    /// slot of an Objective-C reference section, an instance variable's
    /// offset variable.
    case pointerSlot
    /// An `adrp` / `add`, or an `adr`, computing the target's address.
    case addressMaterialization
    /// A literal `ldr` of a slot within a megabyte — what ld64 makes of an
    /// `adrp` / `ldr` pair whose slot is that close.
    case literalLoad
    /// A call or a jump through a register: `blr`, `br`, and their
    /// authenticating forms. Its evidence says what is known about it.
    case indirect
}
