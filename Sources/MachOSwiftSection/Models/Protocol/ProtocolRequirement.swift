import MachOKit
import MachOMacro
import MachOFoundation

public struct ProtocolRequirement: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
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

@MachOImageAllMembersGenerator
extension ProtocolRequirement {
    public func defaultImplementationSymbols(in machOFile: MachOFile) throws -> Symbols? {
        guard layout.defaultImplementation.isValid else { return nil }
        return try layout.defaultImplementation.resolve(from: offset(of: \.defaultImplementation), in: machOFile)
    }
}
