import Foundation
import MachOKit
import MachOBase

public protocol TypeMetadataHeaderProtocol: TypeMetadataLayoutPrefixProtocol, TypeMetadataHeaderBaseProtocol where Layout: TypeMetadataHeaderLayout {}
