import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ObjCProtocolPrefix {
    public struct Layout: LayoutProtocol {
        public let isa: RawPointer
        public let name: Pointer<String>
    }
}

// MARK: - ReadingContext Support

extension ObjCProtocolPrefix {
    public func name(in context: some ReadingContext) throws -> String {
        try layout.name.resolve(in: context)
    }

    public func mangledName(in context: some ReadingContext) throws -> MangledName {
        try layout.name.resolveAny(in: context)
    }
}
