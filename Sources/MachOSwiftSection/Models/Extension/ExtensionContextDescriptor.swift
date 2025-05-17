import Foundation
import MachOKit

public struct ExtensionContextDescriptor: ExtensionContextDescriptorProtocol {
    public struct Layout: ExtensionContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer<ContextDescriptorWrapper?>
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
    public func extendedContext(in machOFile: MachOFile) throws -> MangledName? {
        try layout.extendedContext.resolve(from: offset + 8, in: machOFile)
    }
}





