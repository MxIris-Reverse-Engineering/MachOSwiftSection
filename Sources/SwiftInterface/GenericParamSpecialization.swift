import Foundation
import MachOSwiftSection

package struct GenericParamSpecialization: Sendable {
    package let metadata: Metadata
    
    package let protocolWitnessTables: [ProtocolWitnessTable]?
}
