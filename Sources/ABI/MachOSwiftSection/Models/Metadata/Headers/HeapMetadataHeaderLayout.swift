import Foundation
import MachOKit
import MachOBase
import Utilities

@Layout
public protocol HeapMetadataHeaderLayout: TypeMetadataLayoutPrefixLayout, HeapMetadataHeaderPrefixLayout, TypeMetadataHeaderBaseLayout {}
