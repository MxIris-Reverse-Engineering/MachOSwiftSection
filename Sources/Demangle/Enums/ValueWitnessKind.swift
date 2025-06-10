enum ValueWitnessKind: UInt64, CaseIterable, CustomStringConvertible, Sendable {
    case allocateBuffer = 0
    case assignWithCopy = 1
    case assignWithTake = 2
    case deallocateBuffer = 3
    case destroy = 4
    case destroyArray = 5
    case destroyBuffer = 6
    case initializeBufferWithCopyOfBuffer = 7
    case initializeBufferWithCopy = 8
    case initializeWithCopy = 9
    case initializeBufferWithTake = 10
    case initializeWithTake = 11
    case projectBuffer = 12
    case initializeBufferWithTakeOfBuffer = 13
    case initializeArrayWithCopy = 14
    case initializeArrayWithTakeFrontToBack = 15
    case initializeArrayWithTakeBackToFront = 16
    case storeExtraInhabitant = 17
    case getExtraInhabitantIndex = 18
    case getEnumTag = 19
    case destructiveProjectEnumData = 20
    case destructiveInjectEnumTag = 21
    case getEnumTagSinglePayload = 22
    case storeEnumTagSinglePayload = 23

    init?(code: String) {
        switch code {
        case "al": self = .allocateBuffer
        case "ca": self = .assignWithCopy
        case "ta": self = .assignWithTake
        case "de": self = .deallocateBuffer
        case "xx": self = .destroy
        case "XX": self = .destroyBuffer
        case "Xx": self = .destroyArray
        case "CP": self = .initializeBufferWithCopyOfBuffer
        case "Cp": self = .initializeBufferWithCopy
        case "cp": self = .initializeWithCopy
        case "Tk": self = .initializeBufferWithTake
        case "tk": self = .initializeWithTake
        case "pr": self = .projectBuffer
        case "TK": self = .initializeBufferWithTakeOfBuffer
        case "Cc": self = .initializeArrayWithCopy
        case "Tt": self = .initializeArrayWithTakeFrontToBack
        case "tT": self = .initializeArrayWithTakeBackToFront
        case "xs": self = .storeExtraInhabitant
        case "xg": self = .getExtraInhabitantIndex
        case "ug": self = .getEnumTag
        case "up": self = .destructiveProjectEnumData
        case "ui": self = .destructiveInjectEnumTag
        case "et": self = .getEnumTagSinglePayload
        case "st": self = .storeEnumTagSinglePayload
        default: return nil
        }
    }

    var description: String {
        switch self {
        case .allocateBuffer: return "allocateBuffer"
        case .assignWithCopy: return "assignWithCopy"
        case .assignWithTake: return "assignWithTake"
        case .deallocateBuffer: return "deallocateBuffer"
        case .destroy: return "destroy"
        case .destroyBuffer: return "destroyBuffer"
        case .initializeBufferWithCopyOfBuffer: return "initializeBufferWithCopyOfBuffer"
        case .initializeBufferWithCopy: return "initializeBufferWithCopy"
        case .initializeWithCopy: return "initializeWithCopy"
        case .initializeBufferWithTake: return "initializeBufferWithTake"
        case .initializeWithTake: return "initializeWithTake"
        case .projectBuffer: return "projectBuffer"
        case .initializeBufferWithTakeOfBuffer: return "initializeBufferWithTakeOfBuffer"
        case .destroyArray: return "destroyArray"
        case .initializeArrayWithCopy: return "initializeArrayWithCopy"
        case .initializeArrayWithTakeFrontToBack: return "initializeArrayWithTakeFrontToBack"
        case .initializeArrayWithTakeBackToFront: return "initializeArrayWithTakeBackToFront"
        case .storeExtraInhabitant: return "storeExtraInhabitant"
        case .getExtraInhabitantIndex: return "getExtraInhabitantIndex"
        case .getEnumTag: return "getEnumTag"
        case .destructiveProjectEnumData: return "destructiveProjectEnumData"
        case .destructiveInjectEnumTag: return "destructiveInjectEnumTag"
        case .getEnumTagSinglePayload: return "getEnumTagSinglePayload"
        case .storeEnumTagSinglePayload: return "storeEnumTagSinglePayload"
        }
    }
}
