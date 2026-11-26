import Foundation
import Testing
import MachOKit
import MachOFoundation
import SwiftInspection
import SwiftObjCInterop
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// The premise the stored property type recovery stands on (evolution
/// proposal `objc-ivar-type-recovery`): with every field-offset symbol of the
/// fixture's `AdaptiveTransitionWidget` stripped, its ivars still carry their
/// names and the encodings the compiler writes — complete for a type
/// Objective-C represents as it is, `?` for a bridged one, empty for a
/// Swift-only property — and each `@objc` one still finds the Objective-C
/// property synthesized on it, `readonly` and `weak` included. Should the
/// compiler ever write them differently, this fails before the printing tests
/// do, and says so.
@Suite(.serialized, ExclusiveImageAccess(ObjCImplementationFixture.moduleName))
struct ObjCImplementationInstanceVariableFactsTests {
    @Test(arguments: [ObjCImplementationFixture.Variant.strippedLocals, .strippedEverything, .optimizedStripped])
    func strippedInstanceVariablesKeepTheirNamesEncodingsAndObjCProperties(variant: ObjCImplementationFixture.Variant) throws {
        let machOFile = try ObjCImplementationFixture.machOFile(variant)
        let facts = try #require(ObjCImplementationClasses.facts(forClassNamed: "AdaptiveTransitionWidget", in: machOFile))
        #expect(facts.evidence.isInferred == (variant == .strippedEverything))
        #expect(facts.instanceVariables.allSatisfy { $0.swiftFieldOffsetSymbolName == nil })
        let encodingsByName = Dictionary(facts.instanceVariables.map { ($0.name, $0.typeEncoding) }, uniquingKeysWith: { first, _ in first })
        #expect(encodingsByName == [
            "containerView": "@\"NSObject\"",
            "buffer": "@\"NSMutableString\"",
            "previousLayout": "@\"<AdaptiveLayout>\"",
            "identifier": "?",
            "observer": "@\"NSObject\"",
            "isAnimated": "B",
            "interactiveProgress": "d",
            "stepCount": "q",
            "revision": "q",
            "selectedRange": "{_NSRange=QQ}",
            "names": "?",
            "payload": "?",
            "transitionAnimations": "",
        ])
        for instanceVariable in facts.instanceVariables where instanceVariable.isObjCVisible {
            #expect(facts.objcProperty(storedIn: instanceVariable, swiftPropertyName: instanceVariable.name) != nil, "\(instanceVariable.name) finds no Objective-C property")
        }
        let identifier = try #require(facts.instanceVariables.first { $0.name == "identifier" })
        #expect(facts.objcProperty(storedIn: identifier, swiftPropertyName: identifier.name)?.isReadOnly == true)
        let revision = try #require(facts.instanceVariables.first { $0.name == "revision" })
        #expect(facts.objcProperty(storedIn: revision, swiftPropertyName: revision.name)?.isReadOnly == true)
        let observer = try #require(facts.instanceVariables.first { $0.name == "observer" })
        #expect(facts.objcProperty(storedIn: observer, swiftPropertyName: observer.name)?.isWeak == true)
        let containerView = try #require(facts.instanceVariables.first { $0.name == "containerView" })
        #expect(facts.objcProperty(storedIn: containerView, swiftPropertyName: containerView.name)?.isReadOnly == false)
    }
}
