import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct GenericRequirementDescriptor {
    public struct Layout: LayoutProtocol {
        public let flags: GenericRequirementFlags
        public let param: RelativeDirectPointer<MangledName>
        public let content: RelativeOffset
    }
}

extension GenericRequirementDescriptor {
    public var content: GenericRequirementContent {
        switch layout.flags.kind {
        case .protocol:
            let ptr = RelativeIndirectableRawPointerIntPair<Bit>(relativeOffsetPlusIndirectAndInt: layout.content)
            if ptr.value.boolValue {
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
        case nil:
            // What the content field holds depends on the kind, and
            // `GenericRequirementContent` has no case for one this reader
            // does not know; this stops the program, as it always has.
            preconditionFailure("generic requirement flags 0x\(String(layout.flags.rawValue, radix: 16)) name a kind this reader does not know")
        }
    }
}

// MARK: - ReadingContext Support

extension GenericRequirementDescriptor {
    public func isContentEqual(to other: GenericRequirementDescriptor, in context: some ReadingContext) -> Bool {
        guard let lhsResolvedParam = try? paramMangledName(in: context), let rhsResolvedParam = try? other.paramMangledName(in: context) else { return false }
        guard let lhsResolvedContent = try? resolvedContent(in: context), let rhsResolvedContent = try? other.resolvedContent(in: context) else { return false }
        return layout.flags == other.flags && lhsResolvedParam == rhsResolvedParam && lhsResolvedContent == rhsResolvedContent
    }

    public func paramMangledName(in context: some ReadingContext) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset(of: \.param))
        return try layout.param.resolve(at: baseAddress, in: context)
    }

    public func type(in context: some ReadingContext) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset(of: \.content))
        return try RelativeDirectPointer<MangledName>(relativeOffset: layout.content).resolve(at: baseAddress, in: context)
    }

    public func resolvedContent(in context: some ReadingContext) throws -> ResolvedGenericRequirementContent {
        let contentOffset = offset(of: \.content)
        let baseAddress = try context.addressFromOffset(contentOffset)
        switch content {
        case .type(let relativeDirectPointer):
            return try .type(relativeDirectPointer.resolve(at: baseAddress, in: context))
        case .protocol(let relativeProtocolDescriptorPointer):
            return try .protocol(relativeProtocolDescriptorPointer.resolve(at: baseAddress, in: context))
        case .layout(let genericRequirementLayoutKind):
            return .layout(genericRequirementLayoutKind)
        case .conformance(let relativeIndirectablePointer):
            return try .conformance(relativeIndirectablePointer.resolve(at: baseAddress, in: context))
        case .invertedProtocols(let invertedProtocols):
            return .invertedProtocols(invertedProtocols)
        }
    }
}
