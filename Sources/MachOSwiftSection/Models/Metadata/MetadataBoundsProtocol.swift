import Foundation
import MachOKit
import MachOExtensions
import MachOReading

public protocol MetadataBoundsProtocol: LocatableLayoutWrapper where Layout: MetadataBoundsLayout {}

extension MetadataBoundsProtocol {
    public var totalSizeInBytes: StoredSize {
        return (StoredSize(layout.negativeSizeInWords) + StoredSize(layout.positiveSizeInWords)) * MemoryLayout<UnsafeRawPointer>.size.cast()
    }

    public var addressPointInBytes: StoredSize {
        return StoredSize(layout.negativeSizeInWords) * MemoryLayout<UnsafeRawPointer>.size.cast()
    }
}
