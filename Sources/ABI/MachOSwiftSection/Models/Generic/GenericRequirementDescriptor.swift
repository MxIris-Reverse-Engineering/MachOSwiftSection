import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct GenericRequirementDescriptor: ResolvableLocatableLayoutWrapper {
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

// MARK: - Deprecated Mach-O and pointer forms

extension GenericRequirementDescriptor {
    @available(*, deprecated, message: "Pass a ReadingContext: isContentEqual(to:in: machO.context).")
    public func isContentEqual(to other: GenericRequirementDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) -> Bool {
        isContentEqual(to: other, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: paramMangledName(in: machO.context).")
    public func paramMangledName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try paramMangledName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: type(in: machO.context).")
    public func type(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try type(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolvedContent(in: machO.context).")
    public func resolvedContent(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ResolvedGenericRequirementContent {
        try resolvedContent(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: isContentEqual(to:in: .inProcess).")
    public func isContentEqual(to other: GenericRequirementDescriptor) -> Bool {
        isContentEqual(to: other, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: paramMangledName(in: .inProcess).")
    public func paramMangledName() throws -> MangledName {
        try paramMangledName(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: type(in: .inProcess).")
    public func type() throws -> MangledName {
        try type(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolvedContent(in: .inProcess).")
    public func resolvedContent() throws -> ResolvedGenericRequirementContent {
        try resolvedContent(in: InProcessContext.shared)
    }
}
