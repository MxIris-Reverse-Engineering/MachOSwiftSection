import MachOKit
import MachOFoundation

public struct ProtocolRequirement: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: ProtocolRequirementFlags
        public let defaultImplementation: RelativeDirectPointer<Symbols?>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ProtocolRequirement {
    public func defaultImplementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Symbols? {
        guard layout.defaultImplementation.isValid else { return nil }
        return try layout.defaultImplementation.resolve(from: offset(of: \.defaultImplementation), in: machO)
    }
}

public struct ProtocolBaseRequirement: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {}

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

// MARK: - ReadingContext Support

extension ProtocolRequirement {
    public func defaultImplementationSymbols<Context: ReadingContext>(in context: Context) throws -> Symbols? {
        guard layout.defaultImplementation.isValid else { return nil }
        return try layout.defaultImplementation.resolve(at: try context.addressFromOffset(offset(of: \.defaultImplementation)), in: context)
    }
}
