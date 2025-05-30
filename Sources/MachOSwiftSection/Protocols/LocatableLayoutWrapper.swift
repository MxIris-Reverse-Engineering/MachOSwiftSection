import MachOKit

public protocol LocatableLayoutWrapper: LayoutWrapper, Resolvable {
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

extension Resolvable where Self: LocatableLayoutWrapper {
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        try machOFile.readElement(offset: fileOffset)
    }
}

extension Resolvable where Self: LocatableLayoutWrapper {
    public static func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> Self {
        try machOImage.assumingElement(offset: imageOffset)
    }
}
