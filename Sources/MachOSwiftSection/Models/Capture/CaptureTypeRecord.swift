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
@LocatableLayoutWrapping
public struct CaptureTypeRecord: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let mangledTypeName: RelativeDirectPointer<MangledName>
    }
}

extension CaptureTypeRecord {
    public func mangledTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        try layout.mangledTypeName.resolve(from: offset(of: \.mangledTypeName), in: machO)
    }
}

extension CaptureTypeRecord {
    public func mangledTypeName() throws -> MangledName {
        try layout.mangledTypeName.resolve(from: pointer(of: \.mangledTypeName))
    }
}

// MARK: - ReadingContext Support

extension CaptureTypeRecord {
    public func mangledTypeName<Context: ReadingContext>(in context: Context) throws -> MangledName {
        try layout.mangledTypeName.resolve(at: try context.addressFromOffset(offset(of: \.mangledTypeName)), in: context)
    }
}
