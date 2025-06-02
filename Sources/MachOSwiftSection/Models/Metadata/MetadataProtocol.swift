import Foundation
import MachOKit
import MachOExtensions
import MachOReading

public protocol MetadataProtocol: ResolvableLocatableLayoutWrapper where Layout: MetadataLayout {}

extension MetadataProtocol {
    public var kind: MetadataKind {
        .enumeratedMetadataKind(layout.kind)
    }
}
