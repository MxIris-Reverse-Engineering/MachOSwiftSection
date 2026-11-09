import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftObjCInterop

extension TypeDefinition {
    /// Reads the Objective-C protocols the class adopts in its own data
    /// (evolution proposal `swift-declared-objc-protocols`) into
    /// ``objcProtocolNames``. Only a class can; a name several classes print
    /// as finds none.
    package func applyObjCProtocolAdoption(in machO: some MachOSwiftSectionRepresentableWithCache) {
        guard typeName.kind == .class,
              let qualifiedName = NodeTypeNaming.nominalQualifiedName(ofDemangledRoot: typeName.node.materialize()),
              let adoption = ObjCProtocolAdoptionIndex.shared.adoption(ofSwiftClassQualifiedName: qualifiedName, in: machO)
        else { return }
        objcProtocolNames = ObjCProtocolNameBuilder.protocolNames(adoption.declaredProtocolRuntimeNames, excluding: adoption.impliedProtocolRuntimeNames, in: machO)
    }
}
