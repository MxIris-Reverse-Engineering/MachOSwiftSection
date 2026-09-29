import Foundation
import MachOBase
import MachOKit

/// Runtime metadata for a `Builtin.Borrow<T>` value (`MetadataKind.borrow`,
/// Swift 6.4 runtime). A borrow's layout is decided by the referent: it is
/// laid out inline like the referent when the referent is at most four
/// words, bitwise-borrowable and not addressable-for-dependencies, and as a
/// single pointer otherwise (`swift_getBorrowRepresentation`). The metadata
/// itself records only the referent; the value witnesses carry the result.
@LocatableLayoutWrapping
public struct BorrowTypeMetadata: MetadataProtocol {
    public struct Layout: BorrowTypeMetadataLayout {
        public let kind: StoredPointer
        public let referent: ConstMetadataPointer<Metadata>
    }
}
