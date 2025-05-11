import MachOKit

public protocol LocatableLayoutWrapper: LayoutWrapper, ResolvableElement {
    var offset: Int { get }

    init(layout: Layout, offset: Int)
}

extension LocatableLayoutWrapper {
    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + MemoryLayout<Layout>.offset(of: keyPath)!
    }

    public func resolvedRelativeOffset(of keyPath: KeyPath<Layout, RelativeOffset>) -> Int {
        return numericCast(offset(of: keyPath) + layout[keyPath: keyPath].cast())
    }
}

extension ResolvableElement where Self: LocatableLayoutWrapper {
    public static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Self {
        let layout: Layout = try machO.readElement(offset: fileOffset)
        return .init(layout: layout, offset: fileOffset)
    }
}
