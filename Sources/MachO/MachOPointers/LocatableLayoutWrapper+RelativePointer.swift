import BinaryParseSupport
import MachOKitExtensions

extension LocatableLayoutWrapper {
    /// The file offset a relative direct pointer field resolves to, or `nil`
    /// when the field is null.
    ///
    /// Every record holding a relative pointer resolves it the same three
    /// ways — check for null, take the field's own location, add the stored
    /// delta — so the key path is the only thing that differs. It also names
    /// the field at the call site, which is what a per-field wrapper property
    /// would have said and nothing more.
    ///
    /// Pure pointer arithmetic: no reader is involved, and the result is in
    /// the same coordinate space as ``offset``. Attributing a symbol to that
    /// offset belongs a layer up, in `SwiftInspection`.
    ///
    /// The key path must address a **stored** property of the concrete
    /// `Layout`. One formed inside a generic context against a layout
    /// *protocol* addresses a witness instead, and the offset lookup behind
    /// this answers nil for it — so a shared implementation over a layout
    /// protocol cannot use this; each conformer must call it itself.
    ///
    /// The field may be any relative pointer, but the offset is always the
    /// **direct** reading. For a relative-*indirectable* field that is only
    /// the target when the indirect bit is clear — when it is set, the offset
    /// names the slot holding the pointer, not the pointee — so such a field's
    /// caller must rule out `isIndirect` itself before trusting the result.
    public func resolvedDirectOffset<Pointer: RelativePointerProtocol>(from keyPath: KeyPath<Layout, Pointer>) -> Int? {
        let pointer = layout[keyPath: keyPath]
        guard pointer.isValid else { return nil }
        return pointer.resolveDirectOffset(from: offset(of: keyPath))
    }
}
