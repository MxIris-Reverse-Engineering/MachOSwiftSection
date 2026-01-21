enum FunctionSigSpecializationParamKind: UInt64, CaseIterable, Sendable {
    case constantPropFunction = 0
    case constantPropGlobal = 1
    case constantPropInteger = 2
    case constantPropFloat = 3
    case constantPropString = 4
    case closureProp = 5
    case boxToValue = 6
    case boxToStack = 7
    case inOutToOut = 8
    case constantPropKeyPath = 9

    case dead = 64
    case ownedToGuaranteed = 128
    case sroa = 256
    case guaranteedToOwned = 512
    case existentialToGeneric = 1024
}

extension FunctionSigSpecializationParamKind {
    var description: String {
        switch self {
        case .boxToValue: return "Value Promoted from Box"
        case .boxToStack: return "Stack Promoted from Box"
        case .constantPropFunction: return "Constant Propagated Function"
        case .constantPropGlobal: return "Constant Propagated Global"
        case .constantPropInteger: return "Constant Propagated Integer"
        case .constantPropFloat: return "Constant Propagated Float"
        case .constantPropKeyPath: return "Constant Propagated KeyPath"
        case .constantPropString: return "Constant Propagated String"
        case .closureProp: return "Closure Propagated"
        case .existentialToGeneric: return "Existential To Protocol Constrained Generic"
        case .dead: return "Dead"
        case .inOutToOut: return "InOut Converted to Out"
        case .ownedToGuaranteed: return "Owned To Guaranteed"
        case .guaranteedToOwned: return "Guaranteed To Owned"
        case .sroa: return "Exploded"
        }
    }
}
