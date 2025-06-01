import MachOKit
import MachOFoundation
import MachOSwiftSectionMacro

public protocol ContextDescriptorProtocol: ResolvableLocatableLayoutWrapper where Layout: ContextDescriptorLayout {}

@MachOImageAllMembersGenerator
extension ContextDescriptorProtocol {
    public func parent(in machOFile: MachOFile) throws -> ResolvableElement<ContextDescriptorWrapper>? {
        guard layout.flags.kind != .module else { return nil }
        return try layout.parent.resolve(from: offset + layout.offset(of: .parent), in: machOFile).asOptional
    }

    public func genericContext(in machOFile: MachOFile) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try GenericContext(contextDescriptor: self, in: machOFile)
    }
}
