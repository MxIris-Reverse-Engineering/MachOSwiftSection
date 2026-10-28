import Foundation
import Testing
@_spi(Internals) @testable import SwiftInspection

/// `ObjCImporterNaming` (evolution proposal `swift-declared-objc-protocols`):
/// the importer's names for the methods of an `@objc` protocol, from the
/// selector and extended type encoding alone.
///
/// The expected names are the real ClangImporter's. They were taken by
/// writing each protocol's binary facts — selectors, extended encodings, the
/// property list, no nullability, no parameter names, Swift classes and
/// protocols under the Swift names a generated header gives them — into an
/// Objective-C header and printing its import with `swift-synthesize-interface`
/// (Swift 6.4.2). Two sources: a probe module with one protocol whose
/// selectors the compiler derived and one written Apple's way, with explicit
/// selectors; and the 11 protocols of Xcode's DVTFoundation.
@Suite
struct ObjCImporterNamingTests {
    private struct Case: CustomTestStringConvertible, Sendable {
        let contextTypeName: String
        let selector: String
        let isClassMethod: Bool
        let encoding: String
        /// The importer's name, `teamName(for:)`.
        let importerName: String
        let throwsError: Bool

        init(_ contextTypeName: String, _ selector: String, isClassMethod: Bool = false, _ encoding: String, _ importerName: String, throwsError: Bool = false) {
            self.contextTypeName = contextTypeName
            self.selector = selector
            self.isClassMethod = isClassMethod
            self.encoding = encoding
            self.importerName = importerName
            self.throwsError = throwsError
        }

        var testDescription: String { "\(contextTypeName) \(selector)" }
    }

    private static let probeDerived = "PublicDerivedSelectors"
    private static let probeExplicit = "PRBExplicitSelectors"

    private static let cases: [Case] = [
        // The probe's selectors the compiler derived from Swift names.
        Case(probeDerived, "nameFor:", #"@"NSString"24@0:8@16"#, "name(for:)"),
        Case(probeDerived, "teamNameFor:error:", #"@"NSString"32@0:8@"NSString"16^@24"#, "teamName(for:)", throwsError: true),
        Case(probeDerived, "hangPointsWithInput:error:", #"@"NSArray"32@0:8@"NSObject"16^@24"#, "hangPoints(withInput:)", throwsError: true),
        Case(probeDerived, "userVisibleRolesForDeveloperTeamId:", #"@"NSArray"24@0:8@"NSString"16"#, "userVisibleRoles(forDeveloperTeamId:)"),
        Case(probeDerived, "perform:with:", #"v32@0:8@"NSString"16@24"#, "perform(_:with:)"),
        Case(probeDerived, "downloadWithIdentifier:completion:", #"v32@0:8@"NSString"16@?<v@?@"NSURL"@"NSError">24"#, "download(withIdentifier:completion:)"),
        Case(probeDerived, "refreshWithCompletionHandler:", #"v24@0:8@?<v@?q@"NSError">16"#, "refresh(completionHandler:)"),
        Case(probeDerived, "tokenAndReturnError:", #"@"NSString"24@0:8^@16"#, "token()", throwsError: true),
        Case(probeDerived, "isEntitlementGrantedWithProfile:entitlement:", #"B32@0:8@"NSObject"16@"NSString"24"#, "isEntitlementGranted(withProfile:entitlement:)"),
        Case(probeDerived, "reload", "v16@0:8", "reload()"),
        Case(probeDerived, "insert:at:", #"v32@0:8@"NSString"16q24"#, "insert(_:at:)"),
        Case(probeDerived, "makeDefault", isClassMethod: true, #"@"NSObject"16@0:8"#, "makeDefault()"),
        Case(probeDerived, "scrollTo:animated:", "v28@0:8q16B24", "scroll(to:animated:)"),
        // The probe's explicit selectors.
        Case(probeExplicit, "nameForObject:", #"@"NSString"24@0:8@16"#, "name(for:)"),
        Case(probeExplicit, "tableView:numberOfRowsInSection:", #"q32@0:8@"NSObject"16q24"#, "tableView(_:numberOfRowsInSection:)"),
        Case(probeExplicit, "indexOfObject:", "q24@0:8@16", "index(of:)"),
        Case(probeExplicit, "removeObjectAtIndex:", "v24@0:8q16", "removeObject(at:)"),
        Case(probeExplicit, "stringByAppendingString:", #"@"NSString"24@0:8@"NSString"16"#, "string(byAppending:)"),
        Case(probeExplicit, "fetchItemsWithIdentifier:completionHandler:", #"v32@0:8@"NSString"16@?<v@?@"NSArray">24"#, "fetchItems(withIdentifier:completionHandler:)"),
        Case(probeExplicit, "objectForKey:", #"@24@0:8@"NSString"16"#, "object(forKey:)"),
        Case(probeExplicit, "setValue:forKey:", #"v32@0:8@16@"NSString"24"#, "setValue(_:forKey:)"),
        Case(probeExplicit, "addObserver:forKeyPath:", #"v32@0:8@"NSObject"16@"NSString"24"#, "addObserver(_:forKeyPath:)"),
        // DVTFoundation's protocols.
        Case("DVTTeamCredential", "tokenAndReturnError:", #"@"NSString"24@0:8^@16"#, "token()", throwsError: true),
        Case("DVTFieldReportDirectSourceProtocol", "hangPointsWithInput:error:", #"@"NSArray"32@0:8@"_TtC13DVTFoundation31DVTFieldReportDirectSourceInput"16^@24"#, "hangPoints(with:)", throwsError: true),
        Case("DVTAppStoreConnectExtensionProtocol", "init", "@16@0:8", "init()"),
        Case("DVTAppStoreConnectExtensionProtocol", "actorForCredentialsProvider:", #"@24@0:8@"<_TtP13DVTFoundation26BackendCredentialsProvider_>"16"#, "actor(for:)"),
        Case("DVTProvisioningProfileEntitlementMatchingProvider", "isEntitlementGrantedWithProfile:entitlement:value:logAspect:", #"B48@0:8@"DVTProvisioningProfile"16@"NSString"24@32@"DVTLogAspect"40"#, "isEntitlementGranted(with:entitlement:value:logAspect:)"),
        Case("DVTRuntimeEnvironmentVariable", "variableFromExistingWithVariable:macros:", #"@"<_TtP13DVTFoundation29DVTRuntimeEnvironmentVariable_>"32@0:8@"<_TtP13DVTFoundation29DVTRuntimeEnvironmentVariable_>"16@"NSDictionary"24"#, "fromExisting(with:macros:)"),
        Case("DVTDownloadableUtilitiesProvider_ObjC", "downloadSimulatorRuntimeCryptexWithAbsoluteAssetID:patchableFrom:progressUpdateBlock:completionHandler:", #"v48@0:8@"MAAbsoluteAssetId"16@"NSArray"24@?<v@?@"_TtC13DVTFoundation29DVTDownloadableProgressUpdate">32@?<v@?@"NSURL"@"NSError">40"#, "downloadSimulatorRuntimeCryptex(with:patchableFrom:progressUpdate:completionHandler:)"),
        Case("DVTDownloadableUtilitiesProvider_ObjC", "cancelDownloadSimulatorRuntimeCryptexWithAbsoluteAssetID:completionHandler:", #"v32@0:8@"MAAbsoluteAssetId"16@?<v@?@"NSError">24"#, "cancelDownloadSimulatorRuntimeCryptex(with:completionHandler:)"),
        Case("DVTDownloadableUtilitiesProvider_ObjC", "mobileAssetAbsoluteIDWithDownloadable:installedOnly:completionHandler:", #"v36@0:8@"_TtC13DVTFoundation15DVTDownloadable"16B24@?<v@?@@"NSError">28"#, "mobileAssetAbsoluteID(with:installedOnly:completionHandler:)"),
        Case("DVTDownloadableUtilitiesProvider_ObjC", "updateDefaultSDKMobileAssetCatalogCatalogStatusWithCompletion:", "v24@0:8@?<v@?>16", "updateDefaultSDKMobileAssetCatalogCatalogStatus(completion:)"),
        Case("BackendCredentialsProvider", "sessionProviderCredentialAndReturnError:", #"@"_TtC13DVTFoundation36DVTServicesSessionProviderCredential"24@0:8^@16"#, "sessionProviderCredential()", throwsError: true),
        Case("DVTActorProtocol", "userVisibleRolesForDeveloperTeamId:", #"@"NSArray"24@0:8@"NSString"16"#, "userVisibleRoles(forDeveloperTeamId:)"),
        Case("DVTActorProtocol", "teamNameFor:error:", #"@"NSString"32@0:8@"NSString"16^@24"#, "teamName(for:)", throwsError: true),
    ]

    private static func spelling(of name: ObjCImporterNaming.ImportedName) -> String {
        "\(name.baseName)(\(name.argumentLabels.map { ($0.isEmpty ? "_" : $0) + ":" }.joined()))"
    }

    private static func importedName(_ testCase: Case, undoesSwiftInsertedWith: Bool) throws -> ObjCImporterNaming.ImportedName {
        let methodType = try #require(ObjCTypeEncodingParser.methodType(from: testCase.encoding), "\(testCase.encoding)")
        return ObjCImporterNaming.importedName(
            selector: testCase.selector,
            isClassMethod: testCase.isClassMethod,
            methodType: methodType,
            contextTypeName: testCase.contextTypeName,
            undoesSwiftInsertedWith: undoesSwiftInsertedWith
        )
    }

    @Test(arguments: cases)
    private func matchesTheImporter(_ testCase: Case) throws {
        let name = try Self.importedName(testCase, undoesSwiftInsertedWith: false)
        #expect(Self.spelling(of: name) == testCase.importerName)
        #expect((name.errorConvention != nil) == testCase.throwsError)
    }

    /// The library's own step, after the importer's: a first label starting
    /// with `with` and going on loses it — the `With` Swift inserts before a
    /// first label that starts with no preposition. A label that is `with`
    /// alone, or an initializer's, stays.
    @Test func undoesTheWithSwiftInserts() throws {
        let expectations: [(selector: String, encoding: String, name: String)] = [
            ("hangPointsWithInput:error:", #"@"NSArray"32@0:8@"NSObject"16^@24"#, "hangPoints(input:)"),
            ("downloadWithIdentifier:completion:", #"v32@0:8@"NSString"16@?<v@?@"NSURL"@"NSError">24"#, "download(identifier:completion:)"),
            ("isEntitlementGrantedWithProfile:entitlement:", #"B32@0:8@"NSObject"16@"NSString"24"#, "isEntitlementGranted(profile:entitlement:)"),
            ("fetchItemsWithIdentifier:completionHandler:", #"v32@0:8@"NSString"16@?<v@?@"NSArray">24"#, "fetchItems(identifier:completionHandler:)"),
            ("loadWithURL:", #"v24@0:8@"NSString"16"#, "load(url:)"),
            ("perform:with:", #"v32@0:8@"NSString"16@24"#, "perform(_:with:)"),
            ("initWithIdentifier:", #"@24@0:8@"NSString"16"#, "init(identifier:)"),
        ]
        for expectation in expectations {
            let methodType = try #require(ObjCTypeEncodingParser.methodType(from: expectation.encoding))
            let name = ObjCImporterNaming.importedName(selector: expectation.selector, isClassMethod: false, methodType: methodType, contextTypeName: "Probe")
            #expect(Self.spelling(of: name) == expectation.name, "\(expectation.selector)")
        }
        // A label left as `with` alone after the type name went stays.
        let directSource = try Self.importedName(Self.cases.first { $0.importerName == "hangPoints(with:)" }!, undoesSwiftInsertedWith: true)
        #expect(Self.spelling(of: directSource) == "hangPoints(with:)")
    }

    @Test func classifiesInitializersSubscriptsAndTheErrorConvention() throws {
        func name(_ selector: String, _ encoding: String, isClassMethod: Bool = false) throws -> ObjCImporterNaming.ImportedName {
            ObjCImporterNaming.importedName(selector: selector, isClassMethod: isClassMethod, methodType: try #require(ObjCTypeEncodingParser.methodType(from: encoding)), contextTypeName: "DerivedSelectors")
        }
        let initializer = try name("initWithIdentifier:", #"@24@0:8@"NSString"16"#)
        #expect(initializer.kind == .initializer)
        #expect(Self.spelling(of: initializer) == "init(identifier:)")
        // `initialize` is not of the `init` family.
        #expect(try name("initialize", "v16@0:8").kind == .method)
        // A class method returning an object is no initializer either.
        #expect(try name("initWithIdentifier:", #"@24@0:8@"NSString"16"#, isClassMethod: true).kind == .method)

        #expect(try name("objectAtIndexedSubscript:", "@24@0:8q16").kind == .subscriptGetter)
        #expect(try name("setObject:atIndexedSubscript:", "v32@0:8@16q24").kind == .subscriptSetter)
        #expect(try name("objectForKeyedSubscript:", "@24@0:8@16").kind == .subscriptGetter)

        let booleanThrowing = try name("saveAndReturnError:", "B24@0:8^@16")
        #expect(booleanThrowing.errorConvention == .booleanResult)
        #expect(Self.spelling(of: booleanThrowing) == "save()")
        #expect(booleanThrowing.parameterIndices.isEmpty)

        let objectThrowing = try name("teamNameFor:error:", #"@"NSString"32@0:8@"NSString"16^@24"#)
        #expect(objectThrowing.errorConvention == .nonNilResult)
        #expect(objectThrowing.parameterIndices == [0])

        // `void` results never follow the error convention.
        let voidResult = try name("validate:error:", "v32@0:8@16^@24")
        #expect(voidResult.errorConvention == nil)
        #expect(voidResult.argumentLabels.count == 2)
    }

    @Test func wordsSplitLikeTheImporter() {
        func words(_ string: String) -> [String] {
            let words = ObjCImporterNaming.Words(string)
            return (0 ..< words.count).map(words.word)
        }
        #expect(words("userVisibleRolesForDeveloperTeamId") == ["user", "Visible", "Roles", "For", "Developer", "Team", "Id"])
        #expect(words("URLForResource") == ["URL", "For", "Resource"])
        #expect(words("URLs") == ["URLs"])
        #expect(words("UTF8String") == ["UTF", "8", "String"])
        #expect(words("NSURL") == ["NSURL"])
        #expect(words("updateDefaultSDKMobileAsset") == ["update", "Default", "SDK", "Mobile", "Asset"])
        #expect(words("snake_case") == ["snake", "_", "case"])
        #expect(ObjCImporterNaming.toLowercaseInitialisms("URLForResource") == "urlForResource")
        #expect(ObjCImporterNaming.toLowercaseInitialisms("UTF8String") == "utf8String")
        #expect(ObjCImporterNaming.toLowercaseWord("URL") == "URL")
        #expect(ObjCImporterNaming.toLowercaseWord("Identifier") == "identifier")
    }

    @Test func partsOfSpeech() {
        #expect(ObjCImporterNaming.partOfSpeech("For") == .preposition)
        #expect(ObjCImporterNaming.partOfSpeech("remove") == .verb)
        #expect(ObjCImporterNaming.partOfSpeech("Appending") == .gerund)
        #expect(ObjCImporterNaming.partOfSpeech("running") == .gerund)
        #expect(ObjCImporterNaming.partOfSpeech("reload") == .verb)
        #expect(ObjCImporterNaming.partOfSpeech("Roles") == .unknown)
    }

    @Test func typeEncodings() throws {
        let method = try #require(ObjCTypeEncodingParser.methodType(from: #"v48@0:8@"MAAbsoluteAssetId"16@"NSArray"24@?<v@?@"_TtC13DVTFoundation29DVTDownloadableProgressUpdate">32@?<v@?@"NSURL"@"NSError">40"#))
        #expect(method.returnType == .void)
        #expect(method.parameterTypes == [
            .object(className: "MAAbsoluteAssetId", protocolNames: []),
            .object(className: "NSArray", protocolNames: []),
            .block(ObjCBlockSignature(returnType: .void, parameterTypes: [.object(className: "_TtC13DVTFoundation29DVTDownloadableProgressUpdate", protocolNames: [])])),
            .block(ObjCBlockSignature(returnType: .void, parameterTypes: [.object(className: "NSURL", protocolNames: []), .object(className: "NSError", protocolNames: [])])),
        ])
        #expect(ObjCTypeEncodingParser.type(from: #"@"NSObject<NSCopying><NSCoding>""#) == .object(className: "NSObject", protocolNames: ["NSCopying", "NSCoding"]))
        #expect(ObjCTypeEncodingParser.type(from: #"@"<NSCopying>""#) == .object(className: nil, protocolNames: ["NSCopying"]))
        #expect(ObjCTypeEncodingParser.type(from: #"{CGRect="origin"{CGPoint="x"d"y"d}"size"{CGSize="width"d"height"d}}"#) == .structure(name: "CGRect"))
        #expect(ObjCTypeEncodingParser.type(from: "r^v") == .pointer(.void, isConst: true))
        #expect(ObjCTypeEncodingParser.type(from: "^?") == .pointer(.unknown, isConst: false))
        #expect(ObjCTypeEncodingParser.propertyType(fromAttributes: #"T@"NSString",N,R"#) == .object(className: "NSString", protocolNames: []))
        #expect(ObjCTypeEncodingParser.propertyType(fromAttributes: "T{_NSRange=QQ},N") == .structure(name: "_NSRange"))
        // `self` and `_cmd` are required.
        #expect(ObjCTypeEncodingParser.methodType(from: "v16") == nil)
    }
}
