import Foundation
import MachOKit
import MachOMacro

@Layout
public protocol StructMetadataLayout: MetadataLayout {
    var descriptor: SignedPointer<StructDescriptor> { get }
}
