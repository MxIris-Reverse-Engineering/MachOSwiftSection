import Foundation
import MachOKit
import MachOFoundation

/// Resolves vtable slot indices for `MethodOverrideDescriptor` values by looking up
/// the original method in the parent class's vtable, caching each parent class's
/// base offset and method-descriptor offsets so that sibling overrides share work.
public struct ParentClassVTableCache {
    private struct Entry {
        let baseOffset: Int
        let methodDescriptorOffsets: [Int]
    }

    private var entriesByParentOffset: [Int: Entry] = [:]

    public init() {}

    /// Returns the absolute vtable slot index for `descriptor`, or `nil` if the
    /// override cannot be resolved (missing original method, missing parent class
    /// context, parent class without a vtable, or original method not found in
    /// the parent's vtable).
    public mutating func slotIndex<MachO: MachOSwiftSectionRepresentableWithCache>(
        for descriptor: MethodOverrideDescriptor,
        in machO: MachO
    ) throws -> Int? {
        guard let methodResult = try descriptor.methodDescriptor(in: machO),
              case .element(let originalMethod) = methodResult else {
            return nil
        }

        guard let classResult = try descriptor.classDescriptor(in: machO),
              case .element(let parentContext) = classResult,
              case .type(.class(let parentClassDescriptor)) = parentContext else {
            return nil
        }

        let parentOffset = parentClassDescriptor.offset

        if entriesByParentOffset[parentOffset] == nil {
            let parentClass = try Class(descriptor: parentClassDescriptor, in: machO)
            if let header = parentClass.vTableDescriptorHeader {
                entriesByParentOffset[parentOffset] = Entry(
                    baseOffset: Int(header.layout.vTableOffset),
                    methodDescriptorOffsets: parentClass.methodDescriptors.map(\.offset)
                )
            }
        }

        guard let cached = entriesByParentOffset[parentOffset],
              let index = cached.methodDescriptorOffsets.firstIndex(of: originalMethod.offset) else {
            return nil
        }

        return cached.baseOffset + index
    }
}
