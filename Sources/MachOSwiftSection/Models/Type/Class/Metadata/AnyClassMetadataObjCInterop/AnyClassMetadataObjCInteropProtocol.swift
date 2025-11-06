import Foundation
import MachOKit
import MachOFoundation

public protocol AnyClassMetadataObjCInteropProtocol: HeapMetadataProtocol where Layout: AnyClassMetadataObjCInteropLayout {}
