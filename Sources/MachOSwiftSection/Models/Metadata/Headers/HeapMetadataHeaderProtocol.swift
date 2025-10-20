import Foundation
import MachOKit
import MachOFoundation


public protocol HeapMetadataHeaderProtocol: ResolvableLocatableLayoutWrapper where Layout: HeapMetadataHeaderLayout {}
