import Foundation
import MachOKit
import MachOReading

public protocol HeapMetadataProtocol: MetadataProtocol where Layout: HeapMetadataLayout {
    associatedtype HeaderType: ResolvableLocatableLayoutWrapper = HeapMetadataHeader
}
