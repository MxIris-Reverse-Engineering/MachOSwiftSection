import Foundation
import MachOFoundation

@Layout
public protocol ExistentialTypeMetadataLayout: MetadataLayout {
    var flags: ExistentialTypeFlags { get }
    var numberOfProtocols: UInt32 { get }
}
