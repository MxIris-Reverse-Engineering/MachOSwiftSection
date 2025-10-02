public enum MetadataKind: UInt32 {
    static let isNonType: UInt32 = 0x400
    static let isNonHeap: UInt32 = 0x200
    static let isRuntimePrivate: UInt32 = 0x100

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

    /// The largest possible non-isa-pointer metadata kind value.
    ///
    /// This is included in the enumeration to prevent against attempts to
    /// exhaustively match metadata kinds. Future Swift runtimes or compilers
    /// may introduce new metadata kinds, so for forward compatibility, the
    /// runtime must tolerate metadata with unknown kinds.
    /// This specific value is not mapped to a valid metadata kind at this time,
    /// however.
    case lastEnumerated = 0x7FF

    var isHeap: Bool {
        rawValue & Self.isNonHeap == 0
    }

    var isType: Bool {
        rawValue & Self.isNonType == 0
    }

    var isRuntimePrivate: Bool {
        rawValue & Self.isRuntimePrivate != 0
    }

    static func enumeratedMetadataKind(_ kind: UInt64) -> Self {
        if kind > lastEnumerated.rawValue.cast() {
            return .class
        } else {
            return .init(rawValue: kind.cast()) ?? .lastEnumerated
        }
    }
    
    var isAnyClass: Bool {
        switch self {
        case .class, .objcClassWrapper, .foreignClass:
            return true
        default:
            return false
        }
    }
    
    var isAnyExistentialType: Bool {
        switch self {
        case .existential, .existentialMetatype:
            return true
        default:
            return false
        }
    }
}
