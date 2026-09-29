import Semantic

/// The printing options whose effect a marked interface records instead of
/// applying — the option names its `VisibilityRegion`s are conditioned on.
///
/// See `SwiftDeclarationPrintConfiguration.marksOptionalContent`. Projecting
/// a marked interface with a configuration's
/// `isVisibilityOptionEnabled(_:resolvesOpaqueTypes:)` gives what printing
/// with that configuration gives.
public enum SwiftVisibilityOption: String, CaseIterable, Sendable {
    case printStrippedSymbolicItem = "swift.printStrippedSymbolicItem"
    case printFieldOffset = "swift.printFieldOffset"
    case printExpandedFieldOffsets = "swift.printExpandedFieldOffsets"
    case printMemberAddress = "swift.printMemberAddress"
    case printVTableOffset = "swift.printVTableOffset"
    case printPWTOffset = "swift.printPWTOffset"
    case printTypeLayout = "swift.printTypeLayout"
    case printEnumLayout = "swift.printEnumLayout"
    case infersObjCOverridesFromSelectorNames = "swift.infersObjCOverridesFromSelectorNames"

    /// What an opaque type resolver registered with the printer supplies:
    /// the constraint after `some`. Off, the interface reads as printed
    /// without such a resolver.
    case opaqueTypeResolution = "swift.opaqueTypeResolution"
}
