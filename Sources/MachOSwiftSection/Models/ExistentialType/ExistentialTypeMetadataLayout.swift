import Foundation
import MachOFoundation
import MachOMacro

@Layout
public protocol ExistentialTypeMetadataLayout: MetadataLayout {
    var flags: ExistentialTypeFlags { get }
    var numberOfProtocols: UInt32 { get }
}
