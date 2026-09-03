import Foundation
import MachOKit
import MachOBase

@Layout
public protocol HeapMetadataHeaderLayout: TypeMetadataLayoutPrefixLayout, HeapMetadataHeaderPrefixLayout, TypeMetadataHeaderBaseLayout {}
