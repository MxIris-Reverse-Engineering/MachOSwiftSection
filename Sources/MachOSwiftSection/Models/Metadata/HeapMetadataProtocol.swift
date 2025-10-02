import Foundation
import MachOKit
import MachOExtensions
import MachOReading
import MachOMacro

public protocol HeapMetadataProtocol: MetadataProtocol where Layout: HeapMetadataLayout {
    associatedtype HeaderType: ResolvableLocatableLayoutWrapper = HeapMetadataHeader
}
