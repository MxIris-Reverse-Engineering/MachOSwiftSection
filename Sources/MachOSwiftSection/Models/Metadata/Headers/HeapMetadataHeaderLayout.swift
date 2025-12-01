import Foundation
import MachOKit
import MachOFoundation

@Layout
public protocol HeapMetadataHeaderLayout: TypeMetadataLayoutPrefixLayout, HeapMetadataHeaderPrefixLayout, TypeMetadataHeaderBaseLayout {}
