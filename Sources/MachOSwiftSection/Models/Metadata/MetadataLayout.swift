import Foundation
import MachOMacro

@Layout
public protocol MetadataLayout: Sendable {
    var kind: StoredPointer { get }
}
