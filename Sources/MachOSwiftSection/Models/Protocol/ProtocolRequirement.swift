import MachOKit
import MachOBase

public struct ProtocolRequirement: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: ProtocolRequirementFlags
        public let defaultImplementation: RelativeDirectRawPointer
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ProtocolRequirement {
    /// File offset of the requirement's default implementation, or `nil`
    /// when the requirement has none. Pure pointer arithmetic on the
    /// descriptor's own offset; symbol attribution is `SwiftInspection`'s
    /// `defaultImplementationSymbols(in:)`, one layer up.
    public var defaultImplementationOffset: Int? {
        guard layout.defaultImplementation.isValid else { return nil }
        return layout.defaultImplementation.resolveDirectOffset(from: offset(of: \.defaultImplementation))
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
    /// The default implementation's location as an address in `context`, or
    /// `nil` when the requirement has none.
    public func defaultImplementationAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let defaultImplementationOffset else { return nil }
        return try context.addressFromOffset(defaultImplementationOffset)
    }
}
