import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

/// A protocol descriptor.
///
/// Protocol descriptors contain information about the contents of a protocol:
/// it's name, requirements, requirement signature, context, and so on. They
/// are used both to identify a protocol and to reason about its contents.
///
/// Only Swift protocols are defined by a protocol descriptor, whereas
/// Objective-C (including protocols defined in Swift as @objc) use the
/// Objective-C protocol layout.
public struct ProtocolDescriptor: ProtocolDescriptorProtocol {
    public struct Layout: ProtocolDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public var name: RelativeDirectPointer<String>
        public var numRequirementsInSignature: UInt32
        public var numRequirements: UInt32
        public var associatedTypes: RelativeDirectPointer<String>
    }

    public var offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }

    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + layoutOffset(of: keyPath)
    }
}

extension ProtocolDescriptor {
    public func associatedTypes<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> [String] {
        guard layout.associatedTypes.isValid else { return [] }
        return try layout.associatedTypes.resolve(from: offset(of: \.associatedTypes), in: machO).components(separatedBy: " ")
    }
}

