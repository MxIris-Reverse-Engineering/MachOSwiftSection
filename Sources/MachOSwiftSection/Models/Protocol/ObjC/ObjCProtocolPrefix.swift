import Foundation
import MachOKit
import MachOFoundation

public struct ObjCProtocolPrefix: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let isa: RawPointer
        public let name: Pointer<String>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ObjCProtocolPrefix {
    public func name<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> String {
        try layout.name.resolve(in: machO)
    }

    public func mangledName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
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
    public func mangledName<Context: ReadingContext>(in context: Context) throws -> MangledName {
        try layout.name.resolveAny(in: context)
    }
}
