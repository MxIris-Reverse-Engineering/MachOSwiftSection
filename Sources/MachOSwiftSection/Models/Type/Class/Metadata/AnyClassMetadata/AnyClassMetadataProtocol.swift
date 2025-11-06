import Foundation
import MachOKit
import MachOFoundation

public protocol AnyClassMetadataProtocol: HeapMetadataProtocol where Layout: AnyClassMetadataLayout {}
