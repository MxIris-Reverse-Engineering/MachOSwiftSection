import Foundation
import MachOKit
import MachOBase

public protocol FinalClassMetadataLayout {
    var descriptor: Pointer<ClassDescriptor?> { get }
}
