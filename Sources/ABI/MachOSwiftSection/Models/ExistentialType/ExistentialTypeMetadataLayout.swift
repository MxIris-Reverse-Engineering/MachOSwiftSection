import Foundation
import MachOBase
import Utilities

@Layout
public protocol ExistentialTypeMetadataLayout: MetadataLayout {
    var flags: ExistentialTypeFlags { get }
    var numberOfProtocols: UInt32 { get }
}
