import Foundation
@_spi(Support) import MachOKit

public protocol SwiftProtocolDescriptorProtocol: _FixupResolvable where LayoutField == SwiftProtocolLayoutField {
    associatedtype Layout: _SwiftProtocolLayoutProtocol
    
    var layout: Layout { get }
    var offset: Int { get }
    
    @_spi(Core)
    init(layout: Layout, offset: Int)
}


