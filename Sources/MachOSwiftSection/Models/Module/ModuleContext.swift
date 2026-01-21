import Foundation
import MachOKit
import MachOFoundation

public struct ModuleContext: TopLevelType, ContextProtocol {
    public let descriptor: ModuleContextDescriptor

    public let name: String

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: ModuleContextDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        self.name = try descriptor.name(in: machO)
    }
    
    public init(descriptor: ModuleContextDescriptor) throws {
        self.descriptor = descriptor
        self.name = try descriptor.name()
    }
}
