import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct AnyLocatableLayoutWrapper<Layout: LayoutProtocol>: ResolvableLocatableLayoutWrapper {}
