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

// MARK: - ReadingContext Support

extension ObjCProtocolPrefix {
    public func name(in context: some ReadingContext) throws -> String {
        try layout.name.resolve(in: context)
    }

    public func mangledName(in context: some ReadingContext) throws -> MangledName {
        try layout.name.resolveAny(in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ObjCProtocolPrefix {
    @available(*, deprecated, message: "Pass a ReadingContext: name(in: machO.context).")
    public func name(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> String {
        try name(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledName(in: machO.context).")
    public func mangledName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try mangledName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: name(in: .inProcess).")
    public func name() throws -> String {
        try name(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledName(in: .inProcess).")
    public func mangledName() throws -> MangledName {
        try mangledName(in: InProcessContext.shared)
    }
}
