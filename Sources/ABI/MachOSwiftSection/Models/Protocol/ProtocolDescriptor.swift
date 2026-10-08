import Foundation
import MachOKit
import MachOBase

/// A protocol descriptor.
///
/// Protocol descriptors contain information about the contents of a protocol:
/// it's name, requirements, requirement signature, context, and so on. They
/// are used both to identify a protocol and to reason about its contents.
///
/// Only Swift protocols are defined by a protocol descriptor, whereas
/// Objective-C (including protocols defined in Swift as @objc) use the
/// Objective-C protocol layout.
@LocatableLayoutWrapping
public struct ProtocolDescriptor: ProtocolDescriptorProtocol {
    public struct Layout: ProtocolDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public var name: RelativeDirectPointer<String>
        public var numRequirementsInSignature: UInt32
        public var numRequirements: UInt32
        public var associatedTypes: RelativeDirectPointer<String>
    }
}

// MARK: - ReadingContext Support

extension ProtocolDescriptor {
    public func associatedTypes(in context: some ReadingContext) throws -> [String] {
        guard layout.associatedTypes.isValid else { return [] }
        return try layout.associatedTypes.resolve(at: try context.addressFromOffset(offset(of: \.associatedTypes)), in: context).components(separatedBy: " ")
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ProtocolDescriptor {
    @available(*, deprecated, message: "Pass a ReadingContext: associatedTypes(in: machO.context).")
    public func associatedTypes(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [String] {
        try associatedTypes(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: associatedTypes(in: .inProcess).")
    public func associatedTypes() throws -> [String] {
        try associatedTypes(in: InProcessContext.shared)
    }
}
