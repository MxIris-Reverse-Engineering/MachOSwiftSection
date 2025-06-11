import Foundation
import MachOKit

public protocol ClassMetadataBoundsProtocol: MetadataBoundsProtocol where Layout: ClassMetadataBoundsLayout {}

extension ClassMetadataBoundsProtocol {}
