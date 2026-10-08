import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct GenericEnvironment: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: GenericEnvironmentFlags
    }
}
