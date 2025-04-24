import Foundation
@_spi(Support) import MachOKit

public protocol SwiftNominalTypeProtocol: _FixupResolvable where LayoutField == SwiftNominalTypeLayoutField {
    associatedtype Layout: _SwiftNominalTypeLayoutProtocol

    var offset: Int { get }

    var layout: Layout { get }

    @_spi(Core)
    init(offset: Int, layout: Layout)
}

extension SwiftNominalTypeProtocol {
    public func name(in machO: MachOFile) -> String {
        let offset = offset + layoutOffset(of: .name) + Int(layout.name)
        return machO.fileHandle.readString(offset: numericCast(offset + machO.headerStartOffset))!
    }

    public var flags: SwiftContextDescriptorFlags {
        .init(layout.flags)
    }

    public func fieldDescriptor(in machO: MachOFile) -> SwiftFieldDescriptor {
        let offset = offset + layoutOffset(of: .fieldDescriptor) + Int(layout.fieldDescriptor)
        let layout: SwiftFieldDescriptor.Layout = machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
        return SwiftFieldDescriptor(offset: offset, layout: layout)
    }
}
