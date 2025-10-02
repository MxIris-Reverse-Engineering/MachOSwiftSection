import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public protocol TypeMetadataHeaderProtocol: TypeMetadataLayoutPrefixProtocol, TypeMetadataHeaderBaseProtocol where Layout: TypeMetadataHeaderLayout {}
