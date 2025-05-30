import Foundation
import MachOKit
import MachOSwiftSectionMacro

public struct ProtocolRequirement: LocatableLayoutWrapper, Resolvable {
    public struct Layout {
        public let flags: ProtocolRequirementFlags
        public let defaultImplementation: RelativeDirectPointer<UnsolvedSymbol?>
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
    public func defaultImplementationSymbol(in machOFile: MachOFile) throws -> UnsolvedSymbol? {
        guard layout.defaultImplementation.isValid else { return nil }
        return try layout.defaultImplementation.resolve(from: offset(of: \.defaultImplementation), in: machOFile)
    }
}
