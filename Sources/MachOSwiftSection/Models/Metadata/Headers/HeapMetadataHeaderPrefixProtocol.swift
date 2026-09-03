import Foundation
import MachOKit
import MachOBase

public protocol HeapMetadataHeaderPrefixProtocol: ResolvableLocatableLayoutWrapper where Layout: HeapMetadataHeaderPrefixLayout {}
