import Foundation
import MachOKit
import MachOBase

/// One captured value's type, as a mangled name.
///
/// The records sit directly after their ``CaptureDescriptor``, in the order
/// the values appear in the closure context or box.
///
/// Mirrors `swift::reflection::CaptureTypeRecord`
/// (`swift/RemoteInspection/Records.h`).
@ResolvableLocatableLayoutWrapper
public struct CaptureTypeRecord {
    public struct Layout: LayoutProtocol {
        public let mangledTypeName: RelativeDirectPointer<MangledName>
    }
}

// MARK: - ReadingContext Support

extension CaptureTypeRecord {
    public func mangledTypeName(in context: some ReadingContext) throws -> MangledName {
        try layout.mangledTypeName.resolve(at: try context.addressFromOffset(offset(of: \.mangledTypeName)), in: context)
    }
}
