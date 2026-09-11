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
    public func resolvedDirectOffset(from keyPath: KeyPath<Layout, RelativeDirectRawPointer>) -> Int? {
        let layoutField = layout[keyPath: keyPath]
        guard layoutField.isValid else { return nil }
        return layoutField.resolveDirectOffset(from: offset(of: keyPath))
    }
}
