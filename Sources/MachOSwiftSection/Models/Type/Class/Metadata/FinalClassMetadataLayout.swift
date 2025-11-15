import Foundation
import MachOKit
import MachOFoundation

public protocol FinalClassMetadataLayout {
    var descriptor: Pointer<ClassDescriptor?> { get }
}
