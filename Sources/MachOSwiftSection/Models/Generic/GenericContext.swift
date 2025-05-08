import Foundation

public struct GenericContext {
    public var offset: Int
    public var size: Int
    public var header: GenericContextDescriptorHeader
    public var parameters: [GenericParamDescriptor] = []
    public var requirements: [GenericRequirementDescriptor] = []
    public var typePackHeader: GenericPackShapeHeader?
    public var typePacks: [GenericPackShapeDescriptor] = []
    public var conditionalInvertibleProtocolSet: InvertibleProtocolSet?
    public var conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount?
    public var conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor] = []
    public var valueHeader: GenericValueHeader?
    public var values: [GenericValueDescriptor] = []
}
