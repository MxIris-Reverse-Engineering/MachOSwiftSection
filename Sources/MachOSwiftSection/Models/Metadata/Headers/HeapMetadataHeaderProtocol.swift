import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public protocol HeapMetadataHeaderProtocol: ResolvableLocatableLayoutWrapper where Layout: HeapMetadataHeaderLayout {}
