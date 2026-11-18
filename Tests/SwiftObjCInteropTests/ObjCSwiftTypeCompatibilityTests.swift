import Foundation
import Testing
@_spi(Internals) import Demangling
@_spi(Internals) @testable import SwiftObjCInterop

/// Whether a Swift member's type can be its Objective-C member's (evolution
/// proposal `swift-first-imported-declarations`), over SceneHosting's symbols
/// on macOS 27.2: only a clear mismatch counts.
@Suite
struct ObjCSwiftTypeCompatibilityTests {
    private static let implementingModuleName = "SceneHosting"

    private func propertyType(_ symbolName: String) throws -> Node {
        try #require(ObjCSwiftTypeCompatibility.propertyType(ofDemangledMember: try demangleAsNode(symbolName)))
    }

    private let object = ObjCEncodedType.object(className: "SHScenePresentationSettings", protocolNames: [])

    @Test func anObjectIsNotAStructOfTheImplementingModule() throws {
        // `settings: SceneHosting.ScenePresentationSettings`, the Swift-only
        // refinement of the Objective-C `settings`.
        let settings = try propertyType("$sSo19SHScenePresentationC12SceneHostingE8settingsAC0cB8SettingsVvg")
        #expect(ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcType: object, swiftType: settings, implementingModuleName: Self.implementingModuleName))
        // A value type of another module may bridge, and an unknown module
        // judges nothing.
        #expect(!ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcType: object, swiftType: settings, implementingModuleName: "OtherModule"))
        #expect(!ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcType: object, swiftType: settings, implementingModuleName: nil))
    }

    @Test func anObjectIsAClassOrABridgedValue() throws {
        // `__layerFilter: __C.SHSceneLayerFilter`.
        let layerFilter = try propertyType("$sSo19SHScenePresentationC12SceneHostingE13__layerFilterSo0a5LayerF0Cvg")
        #expect(!ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcType: object, swiftType: layerFilter, implementingModuleName: Self.implementingModuleName))
        // `isActive: Swift.Bool`, a struct of the standard library.
        let isActive = try propertyType("$sSo19SHScenePresentationC12SceneHostingE8isActiveSbvg")
        #expect(!ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcType: object, swiftType: isActive, implementingModuleName: Self.implementingModuleName))
        #expect(!ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcType: .bool, swiftType: isActive, implementingModuleName: Self.implementingModuleName))
    }

    @Test func aScalarIsNotAReference() throws {
        // `scene: __C.FBScene?`: the optional is looked through.
        let scene = try propertyType("$sSo19SHScenePresentationC12SceneHostingE5sceneSo7FBSceneCSgvg")
        #expect(ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcType: .longLong, swiftType: scene, implementingModuleName: Self.implementingModuleName))
        #expect(!ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcType: .object(className: "FBScene", protocolNames: []), swiftType: scene, implementingModuleName: Self.implementingModuleName))
    }

    @Test func aMethodComparesItsParametersAndResult() throws {
        // `isHosting(sceneLayer: __C.FBSceneLayer) -> Swift.Bool` against
        // `- (BOOL)isHostingSceneLayer:(id)`.
        let root = try demangleAsNode("$sSo19SHScenePresentationC12SceneHostingE02isD010sceneLayerSbSo07FBSceneG0C_tF")
        let functionType = try #require(ObjCSwiftTypeCompatibility.functionType(ofDemangledMember: root))
        let methodType = try #require(ObjCTypeEncodingParser.methodType(from: "B24@0:8@16", matchingArgumentsOf: "isHostingSceneLayer:"))
        #expect(!ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcMethodType: methodType, swiftFunctionType: functionType, comparesResult: true, implementingModuleName: Self.implementingModuleName))
        // A scalar parameter where Swift takes a class.
        let scalarParameter = try #require(ObjCTypeEncodingParser.methodType(from: "B24@0:8q16", matchingArgumentsOf: "isHostingSceneLayer:"))
        #expect(ObjCSwiftTypeCompatibility.isClearlyIncompatible(objcMethodType: scalarParameter, swiftFunctionType: functionType, comparesResult: true, implementingModuleName: Self.implementingModuleName))
    }
}
