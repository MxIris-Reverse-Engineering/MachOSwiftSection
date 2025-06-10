import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public struct GenericRequirementDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let flags: GenericRequirementFlags
        public let param: RelativeDirectPointer<MangledName>
        public let content: RelativeOffset
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}


@MachOImageAllMembersGenerator
extension GenericRequirementDescriptor {
    //@MachOImageGenerator
    public func paramManagedName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.param.resolve(from: offset(of: \.param), in: machOFile)
    }

    //@MachOImageGenerator
    public func type(in machOFile: MachOFile) throws -> MangledName {
        return try RelativeDirectPointer<MangledName>(relativeOffset: layout.content).resolve(from: offset(of: \.content), in: machOFile)
    }

    public var content: GenericRequirementContent {
        switch layout.flags.kind {
        case .protocol:
            let ptr = RelativeIndirectableRawPointerIntPair<Bool>(relativeOffsetPlusIndirectAndInt: layout.content)
            if ptr.value {
                return .protocol(.objcPointer(.init(relativeOffsetPlusIndirectAndInt: layout.content)))
            } else {
                return .protocol(.swiftPointer(.init(relativeOffsetPlusIndirectAndInt: layout.content)))
            }
        case .sameType,
             .baseClass,
             .sameShape:
            return .type(.init(relativeOffset: layout.content))
        case .sameConformance:
            return .conformance(.init(relativeOffsetPlusIndirect: layout.content))
        case .invertedProtocols:
            var value = layout.content
            return .invertedProtocols(withUnsafeBytes(of: &value) {
                $0.load(as: GenericRequirementContent.InvertedProtocols.self)
            })
        case .layout:
            return .layout(.init(rawValue: layout.content.cast())!)
        }
    }

    //@MachOImageGenerator
    public func resolvedContent(in machOFile: MachOFile) throws -> ResolvedGenericRequirementContent {
        let offset = offset(of: \.content)
        switch content {
        case .type(let relativeDirectPointer):
            return try .type(relativeDirectPointer.resolve(from: offset, in: machOFile))
        case .protocol(let relativeProtocolDescriptorPointer):
            return try .protocol(relativeProtocolDescriptorPointer.resolve(from: offset, in: machOFile))
        case .layout(let genericRequirementLayoutKind):
            return .layout(genericRequirementLayoutKind)
        case .conformance(let relativeIndirectablePointer):
            return try .conformance(relativeIndirectablePointer.resolve(from: offset, in: machOFile))
        case .invertedProtocols(let invertedProtocols):
            return .invertedProtocols(invertedProtocols)
        }
    }
}
