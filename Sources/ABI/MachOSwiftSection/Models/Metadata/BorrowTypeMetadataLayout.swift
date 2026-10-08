import Foundation
import MachOBase

/// The layout of `Builtin.Borrow<T>` metadata (`TargetBorrowTypeMetadata`,
/// Swift 6.4): the common metadata header followed by one pointer to the
/// referent type's metadata.
@Layout
public protocol BorrowTypeMetadataLayout: MetadataLayout {
    var referent: ConstMetadataPointer<Metadata> { get }
}
