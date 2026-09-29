import Foundation
import MachOBase

@Layout
public protocol ExistentialTypeMetadataLayout: MetadataLayout {
    var flags: ExistentialTypeFlags { get }
    var numberOfProtocols: UInt32 { get }
}
