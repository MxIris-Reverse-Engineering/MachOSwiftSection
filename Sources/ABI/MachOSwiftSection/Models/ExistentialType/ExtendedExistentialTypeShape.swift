import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ExtendedExistentialTypeShape {
    public struct Layout: LayoutProtocol {
        public let flags: ExtendedExistentialTypeShapeFlags
        public let existentialType: RelativeDirectPointer<MangledName>
        public let requirementSignatureHeader: GenericContextDescriptorHeader.Layout
    }
}

// MARK: - ReadingContext Support

extension ExtendedExistentialTypeShape {
    public func existentialType(in context: some ReadingContext) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset(of: \.existentialType))
        return try layout.existentialType.resolve(at: baseAddress, in: context)
    }
}

public struct ExtendedExistentialTypeShapeFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
