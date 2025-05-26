import MachOKit
import MachOSwiftSectionMacro

public protocol ContextDescriptorProtocol: LocatableLayoutWrapper where Layout: ContextDescriptorLayout {}

@MachOImageAllMembersGenerator
extension ContextDescriptorProtocol {
    public func parent(in machOFile: MachOFile) throws -> ResolvableElement<ContextDescriptorWrapper>? {
        guard layout.flags.kind != .module else { return nil }
        return try layout.parent.resolve(from: offset + layout.offset(of: .parent), in: machOFile).asOptional
    }

    public func genericContext(in machOFile: MachOFile) throws -> GenericContext? {
        return try GenericContext(contextDescriptor: self, in: machOFile)
    }
}
