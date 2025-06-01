import Foundation
import MachOKit
import MachOSwiftSectionMacro

@Layout
public protocol StructMetadataLayout: MetadataLayout {
    var descriptor: SignedPointer<StructDescriptor> { get }
}
