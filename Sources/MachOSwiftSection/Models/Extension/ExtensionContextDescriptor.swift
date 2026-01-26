import Foundation
import MachOKit
import MachOFoundation

public struct ExtensionContextDescriptor: ExtensionContextDescriptorProtocol {
    public struct Layout: ExtensionContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public let extendedContext: RelativeDirectPointer<MangledName?>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ExtensionContextDescriptorProtocol {
    public func extendedContext<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName? {
        try layout.extendedContext.resolve(from: offset + layout.offset(of: .extendedContext), in: machO)
    }
}

extension ExtensionContextDescriptorProtocol {
    public func extendedContext() throws -> MangledName? {
        try layout.extendedContext.resolve(from: layout.pointer(from: asPointer, of: .extendedContext))
    }
}

// MARK: - ReadingContext Support

extension ExtensionContextDescriptorProtocol {
    public func extendedContext<Context: ReadingContext>(in context: Context) throws -> MangledName? {
        let baseAddress = try context.addressFromOffset(offset)
        return try layout.extendedContext.resolve(at: context.advanceAddress(baseAddress, by: layout.offset(of: .extendedContext)), in: context)
    }
}
