import Foundation
@_spi(Support) import MachOKit

public struct SwiftNominalTypeDescriptor: LayoutWrapperWithOffset, SwiftNominalTypeDescriptorProtocol {
    public struct Layout: _SwiftNominalTypeLayoutProtocol {
        public typealias Pointer = Int32

        public var flags: UInt32

        public var parent: Int32

        public var name: Int32

        public var accessFunction: Int32

        public var fieldDescriptor: Int32
    }

    public var layout: Layout
    public var offset: Int

    @_spi(Core)
    public init(offset: Int, layout: Layout) {
        self.layout = layout
        self.offset = offset
    }

    public func layoutOffset(of field: SwiftNominalTypeLayoutField) -> Int {
        let keyPath: PartialKeyPath<Layout>

        switch field {
        case .flags:
            keyPath = \.flags
        case .parent:
            keyPath = \.parent
        case .name:
            keyPath = \.name
        case .accessFunction:
            keyPath = \.accessFunction
        case .fieldDescriptor:
            keyPath = \.fieldDescriptor
        }

        return layoutOffset(of: keyPath)
    }
}

extension SwiftNominalTypeDescriptor {
    public func name(in machO: MachOFile) -> String? {
        let offset = offset + layoutOffset(of: .name) + Int(layout.name)
        return machO.fileHandle.readString(offset: numericCast(offset + machO.headerStartOffset))
    }

    public var flags: SwiftContextDescriptorFlags {
        .init(rawValue: layout.flags)
    }

    public func fieldDescriptor(in machO: MachOFile) -> SwiftFieldDescriptor {
        let offset = offset + layoutOffset(of: .fieldDescriptor) + Int(layout.fieldDescriptor)
        let layout: SwiftFieldDescriptor.Layout = machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
        return SwiftFieldDescriptor(offset: offset, layout: layout)
    }
}
