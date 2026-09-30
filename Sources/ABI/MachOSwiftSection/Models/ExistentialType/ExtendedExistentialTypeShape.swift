import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ExtendedExistentialTypeShape: ResolvableLocatableLayoutWrapper {
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

// MARK: - Deprecated Mach-O and pointer forms

extension ExtendedExistentialTypeShape {
    @available(*, deprecated, message: "Pass a ReadingContext: existentialType(in: machO.context).")
    public func existentialType(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try existentialType(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: existentialType(in: .inProcess).")
    public func existentialType() throws -> MangledName {
        try existentialType(in: InProcessContext.shared)
    }
}

public struct ExtendedExistentialTypeShapeFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
