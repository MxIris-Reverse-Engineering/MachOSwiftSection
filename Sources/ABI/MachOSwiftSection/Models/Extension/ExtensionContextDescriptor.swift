import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ExtensionContextDescriptor: ExtensionContextDescriptorProtocol {
    public struct Layout: ExtensionContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public let extendedContext: RelativeDirectPointer<MangledName?>
    }
}

// MARK: - ReadingContext Support

extension ExtensionContextDescriptorProtocol {
    public func extendedContext(in context: some ReadingContext) throws -> MangledName? {
        let baseAddress = try context.addressFromOffset(offset)
        return try layout.extendedContext.resolve(at: context.advanceAddress(baseAddress, by: layout.offset(of: .extendedContext)), in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ExtensionContextDescriptorProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: extendedContext(in: machO.context).")
    public func extendedContext(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName? {
        try extendedContext(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: extendedContext(in: .inProcess).")
    public func extendedContext() throws -> MangledName? {
        try extendedContext(in: InProcessContext.shared)
    }
}
