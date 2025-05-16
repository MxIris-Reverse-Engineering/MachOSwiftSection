import MachOKit

public protocol LocatableLayoutWrapper: LayoutWrapper, Resolvable {
    var offset: Int { get }

    init(layout: Layout, offset: Int)
}

extension LocatableLayoutWrapper {
    public func fileOffset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + MemoryLayout<Layout>.offset(of: keyPath)!
    }

    public func resolvedRelativeOffset(of keyPath: KeyPath<Layout, RelativeOffset>) -> Int {
        return numericCast(fileOffset(of: keyPath) + layout[keyPath: keyPath].cast())
    }
}


extension Resolvable where Self: LocatableLayoutWrapper {
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        let layout: Layout = try machOFile.readElement(offset: fileOffset)
        return .init(layout: layout, offset: fileOffset)
    }
}
