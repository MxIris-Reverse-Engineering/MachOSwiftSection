/// How much memory the collections and strings the analyzer keeps take,
/// estimated from their capacities and element strides: what a host counts
/// against its memory budget. Allocator rounding is left out; a heap object's
/// header is counted as 32 bytes.
enum ApproximateSize {
    private static let heapObjectHeaderByteCount = 32

    static func of<Element>(_ array: [Element]) -> Int {
        array.capacity == 0 ? 0 : heapObjectHeaderByteCount + array.capacity * MemoryLayout<Element>.stride
    }

    static func of<Element>(_ set: Set<Element>) -> Int {
        hashTableByteCount(capacity: set.capacity, bucketStride: MemoryLayout<Element>.stride)
    }

    static func of<Key, Value>(_ dictionary: [Key: Value]) -> Int {
        hashTableByteCount(capacity: dictionary.capacity, bucketStride: MemoryLayout<Key>.stride + MemoryLayout<Value>.stride)
    }

    /// A string's own storage: none for one of up to 15 UTF-8 bytes, which
    /// is stored inline.
    static func of(_ string: String) -> Int {
        let byteCount = string.utf8.count
        return byteCount <= 15 ? 0 : heapObjectHeaderByteCount + byteCount + 1
    }

    /// A native hash table: a power of two of buckets, at most three quarters
    /// full, and a bit per bucket saying which are.
    private static func hashTableByteCount(capacity: Int, bucketStride: Int) -> Int {
        guard capacity > 0 else { return 0 }
        var bucketCount = 1
        while bucketCount * 3 / 4 < capacity {
            bucketCount <<= 1
        }
        return heapObjectHeaderByteCount + bucketCount * bucketStride + bucketCount / 8
    }
}
