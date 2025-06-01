import Foundation
import MachOSwiftSectionMacro

@Layout
public protocol MetadataLayout {
    var kind: StoredPointer { get }
}
