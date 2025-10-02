import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

@Layout
public protocol HeapMetadataHeaderLayout: TypeMetadataLayoutPrefixLayout, HeapMetadataHeaderPrefixLayout, TypeMetadataHeaderBaseLayout {}
