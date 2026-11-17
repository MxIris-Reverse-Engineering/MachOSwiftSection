import Foundation
import SwiftDeclaration

/// An Objective-C member a header marks `NS_REFINED_FOR_SWIFT`, as the image's
/// Swift side shows it (evolution proposal `swift-first-imported-declarations`).
/// The binary keeps no trace of the macro; a host that prints the header puts
/// it back on the member's declaration — MachOObjCSection's
/// `ObjCSwiftImportNotes` takes the same keys, the ones an API notes file uses.
///
/// ```swift
/// let definition = indexer.objcImportedClassDefinition(named: "SHScenePresentation")!
/// for refinedMember in try printer.objcMembersRefinedForSwift(in: definition) {
///     // .property(name: "layerFilter", isClassProperty: false), .prefixedSwiftMember
///     // .property(name: "settings", isClassProperty: false), .nameTakenBySwiftDeclaration
/// }
/// ```
public struct ObjCRefinedForSwiftMember: Sendable, Hashable {
    /// The member, keyed as an API notes file keys it.
    public enum Member: Sendable, Hashable {
        /// A property by its name in the property list — `@property`'s.
        case property(name: String, isClassProperty: Bool)
        /// A method or an initializer by its selector.
        case method(selector: String, isClassMethod: Bool)
    }

    /// What shows the member is refined.
    public enum Evidence: Sendable, Hashable {
        /// A Swift member named with the importer's `__` prefix implements it
        /// (`__layerFilter` answers `layerFilter`).
        case prefixedSwiftMember
        /// No Swift member implements it, and a Swift property of the same
        /// plain name has a type it cannot have (`settings` is a struct of
        /// the module's own): Swift knows the Objective-C property by another
        /// name. Inferred for properties only — methods can be overloaded by
        /// type, so a shared name proves nothing about them.
        case nameTakenBySwiftDeclaration
    }

    public let member: Member
    public let evidence: Evidence

    public init(member: Member, evidence: Evidence) {
        self.member = member
        self.evidence = evidence
    }
}

extension ObjCRefinedForSwiftMember {
    init(member objcMember: ObjCImportedMemberDefinition, refinement: ObjCImplementingSwiftMembers.Refinement) {
        let member: Member = switch objcMember.kind {
        case .property:
            .property(name: objcMember.objcPropertyName ?? objcMember.selector, isClassProperty: objcMember.isClassMember)
        case .method, .initializer, .factoryInitializer, .subscript:
            .method(selector: objcMember.selector, isClassMethod: objcMember.isClassMember || objcMember.kind == .factoryInitializer)
        }
        let evidence: Evidence = switch refinement {
        case .answeredUnderPrefixedName: .prefixedSwiftMember
        case .nameTakenByAnotherDeclaration: .nameTakenBySwiftDeclaration
        }
        self.init(member: member, evidence: evidence)
    }
}
