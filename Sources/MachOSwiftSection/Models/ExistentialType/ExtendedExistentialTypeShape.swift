import Foundation
import MachOKit
import MachOFoundation

public struct ExtendedExistentialTypeShape: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: ExtendedExistentialTypeShapeFlags
        public let existentialType: RelativeDirectPointer<MangledName>
        public let requirementSignatureHeader: GenericContextDescriptorHeader.Layout
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ExtendedExistentialTypeShape {
    public func existentialType<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        try layout.existentialType.resolve(from: offset(of: \.existentialType), in: machO)
    }
}

extension ExtendedExistentialTypeShape {
    public func existentialType() throws -> MangledName {
        try layout.existentialType.resolve(from: pointer(of: \.existentialType))
    }
}

// MARK: - ReadingContext Support

extension ExtendedExistentialTypeShape {
    public func existentialType<Context: ReadingContext>(in context: Context) throws -> MangledName {
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
