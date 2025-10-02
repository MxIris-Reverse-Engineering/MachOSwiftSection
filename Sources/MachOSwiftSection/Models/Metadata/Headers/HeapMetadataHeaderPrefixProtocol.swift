import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public protocol HeapMetadataHeaderPrefixProtocol: ResolvableLocatableLayoutWrapper where Layout: HeapMetadataHeaderPrefixLayout {}
