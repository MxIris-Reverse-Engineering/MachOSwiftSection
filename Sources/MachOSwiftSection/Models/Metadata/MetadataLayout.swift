import Foundation
import MachOMacro

@Layout
public protocol MetadataLayout {
    var kind: StoredPointer { get }
}
