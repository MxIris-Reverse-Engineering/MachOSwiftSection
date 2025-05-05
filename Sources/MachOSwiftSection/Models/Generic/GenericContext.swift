import Foundation

public struct GenericContext<Header> {
    public let offset: Int
    public let header: Header
    public let parameters: [GenericParamDescriptor]
    public let requirements: [GenericRequirementDescriptor]
    public let typePackHeader: GenericPackShapeHeader
    public let typePacks: [GenericPackShapeDescriptor]
    public let conditionalInvertibleProtocolSet: InvertibleProtocolSet?
    public let conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor]
    public let valueHeader: GenericValueHeader
    public let values: [GenericValueDescriptor]
}
