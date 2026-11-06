import Foundation
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct GenericEnvironment {
    public struct Layout: LayoutProtocol {
        public let flags: GenericEnvironmentFlags
    }
}
