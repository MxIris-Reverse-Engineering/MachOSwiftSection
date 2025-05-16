public enum MetadataKind: StoredPointer {
    
    static let isNonType: StoredPointer = 0x400
    static let isNonHeap: StoredPointer = 0x200
    static let isRuntimePrivate: StoredPointer = 0x100
    
    case `class` = 0
    /// 0 | Self.isNonHeap
    case `struct` = 0x200
    /// 1 | Self.isNonHeap
    case `enum` = 0x201
    /// 2 | Self.isNonHeap
    case `optional` = 0x202
    /// 3 | Self.isNonHeap
    case foreignClass = 0x203
    /// 4 | Self.isNonHeap
    case foreignReferenceType = 0x204
    /// 0 | Self.isNonHeap | Self.isRuntimePrivate
    case opaque = 0x300
    /// 1 | Self.isNonHeap | Self.isRuntimePrivate
    case tuple = 0x301
    /// 2 | Self.isNonHeap | Self.isRuntimePrivate
    case function = 0x302
    /// 3 | Self.isNonHeap | Self.isRuntimePrivate
    case existential = 0x303
    /// 4 | Self.isNonHeap | Self.isRuntimePrivate
    case metatype = 0x304
    /// 5 | Self.isNonHeap | Self.isRuntimePrivate
    case objcClassWrapper = 0x305
    /// 6 | Self.isNonHeap | Self.isRuntimePrivate
    case existentialMetatype = 0x306
    /// 7 | Self.isNonHeap | Self.isRuntimePrivate
    case extendedExistential = 0x307
    /// 8 | Self.isNonHeap | Self.isRuntimePrivate
    case fixedArray = 0x308
    /// 0 | Self.isNonType
    case heapLocalVariable = 0x400
    /// 1 | Self.isNonType | Self.isRuntimePrivate
    case errorObject = 0x501
    /// 2 | Self.isNonType | Self.isRuntimePrivate
    case task = 0x502
    /// 3 | Self.isNonType | Self.isRuntimePrivate
    case job = 0x503
}
