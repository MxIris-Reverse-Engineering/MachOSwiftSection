import Foundation
import MachOKit
import MachOFoundation

public struct GenericRequirementDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
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

extension GenericRequirementDescriptor {
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
}

extension GenericRequirementDescriptor {
    public func isContentEqual<MachO: MachOSwiftSectionRepresentableWithCache>(to other: GenericRequirementDescriptor, in machO: MachO) -> Bool {
        guard let lhsResolvedParam = try? paramMangledName(in: machO), let rhsResolvedParam = try? other.paramMangledName(in: machO) else { return false }
        guard let lhsResolvedContent = try? resolvedContent(in: machO), let rhsResolvedContent = try? other.resolvedContent(in: machO) else { return false }
        return layout.flags == other.flags && lhsResolvedParam == rhsResolvedParam && lhsResolvedContent == rhsResolvedContent
    }

    public func paramMangledName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        return try layout.param.resolve(from: offset(of: \.param), in: machO)
    }

    public func type<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        return try RelativeDirectPointer<MangledName>(relativeOffset: layout.content).resolve(from: offset(of: \.content), in: machO)
    }

    public func resolvedContent<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ResolvedGenericRequirementContent {
        let offset = offset(of: \.content)
        switch content {
        case .type(let relativeDirectPointer):
            return try .type(relativeDirectPointer.resolve(from: offset, in: machO))
        case .protocol(let relativeProtocolDescriptorPointer):
            return try .protocol(relativeProtocolDescriptorPointer.resolve(from: offset, in: machO))
        case .layout(let genericRequirementLayoutKind):
            return .layout(genericRequirementLayoutKind)
        case .conformance(let relativeIndirectablePointer):
            return try .conformance(relativeIndirectablePointer.resolve(from: offset, in: machO))
        case .invertedProtocols(let invertedProtocols):
            return .invertedProtocols(invertedProtocols)
        }
    }
}

extension GenericRequirementDescriptor {
    public func isContentEqual(to other: GenericRequirementDescriptor) -> Bool {
        guard let lhsResolvedParam = try? paramMangledName(), let rhsResolvedParam = try? other.paramMangledName() else { return false }
        guard let lhsResolvedContent = try? resolvedContent(), let rhsResolvedContent = try? other.resolvedContent() else { return false }
        return layout.flags == other.flags && lhsResolvedParam == rhsResolvedParam && lhsResolvedContent == rhsResolvedContent
    }

    public func paramMangledName() throws -> MangledName {
        return try layout.param.resolve(from: pointer(of: \.param))
    }

    public func type() throws -> MangledName {
        return try RelativeDirectPointer<MangledName>(relativeOffset: layout.content).resolve(from: pointer(of: \.content))
    }

    public func resolvedContent() throws -> ResolvedGenericRequirementContent {
        let pointer = try pointer(of: \.content)
        switch content {
        case .type(let relativeDirectPointer):
            return try .type(relativeDirectPointer.resolve(from: pointer))
        case .protocol(let relativeProtocolDescriptorPointer):
            return try .protocol(relativeProtocolDescriptorPointer.resolve(from: pointer))
        case .layout(let genericRequirementLayoutKind):
            return .layout(genericRequirementLayoutKind)
        case .conformance(let relativeIndirectablePointer):
            return try .conformance(relativeIndirectablePointer.resolve(from: pointer))
        case .invertedProtocols(let invertedProtocols):
            return .invertedProtocols(invertedProtocols)
        }
    }
}
