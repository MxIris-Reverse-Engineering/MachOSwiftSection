import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
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
