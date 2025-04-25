import Foundation
@_spi(Support) import MachOKit

public protocol SwiftNominalTypeDescriptorProtocol: _FixupResolvable where LayoutField == SwiftNominalTypeLayoutField {
    associatedtype Layout: _SwiftNominalTypeLayoutProtocol

    var offset: Int { get }

    var layout: Layout { get }

    @_spi(Core)
    init(offset: Int, layout: Layout)
}


