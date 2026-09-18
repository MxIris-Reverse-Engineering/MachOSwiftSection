import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ObjCProtocolPrefix: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let isa: RawPointer
        public let name: Pointer<String>
    }
}

extension ObjCProtocolPrefix {
    public func name(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> String {
        try layout.name.resolve(in: machO)
    }

    public func mangledName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try layout.name.resolveAny(in: machO)
    }

    public func name() throws -> String {
        try layout.name.resolve()
    }

    public func mangledName() throws -> MangledName {
        try layout.name.resolveAny()
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
