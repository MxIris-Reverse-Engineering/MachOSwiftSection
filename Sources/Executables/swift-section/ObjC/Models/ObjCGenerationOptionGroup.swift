import ArgumentParser
import ObjCDeclarationRendering

/// The ten switches of ``ObjCGenerationOptions``, one flag each.
///
/// Every one defaults to off, so a bare `swift-section objc dump` prints the
/// declarations exactly as the metadata describes them — nothing removed,
/// nothing annotated. That matches the library's ``ObjCGenerationOptions``
/// default and keeps "what the binary says" the baseline you opt away from.
struct ObjCGenerationOptionGroup: ParsableArguments, Sendable {
    @Flag(help: "Drop the <Protocol, …> conformance list, and the members those protocols already declare.")
    var stripProtocolConformance: Bool = false

    @Flag(help: "Drop members that merely override a superclass member. In file mode the superclass chain can be shorter, so this strips less — see the CLI guide.")
    var stripOverrides: Bool = false

    @Flag(help: "Drop ivars synthesized by @property.")
    var stripSynthesizedIvars: Bool = false

    @Flag(help: "Drop getters and setters synthesized by @property.")
    var stripSynthesizedMethods: Bool = false

    @Flag(help: "Drop the .cxx_construct method.")
    var stripCtorMethod: Bool = false

    @Flag(help: "Drop the .cxx_destruct method.")
    var stripDtorMethod: Bool = false

    @Flag(help: "Append an offset comment after each ivar.")
    var emitIvarOffsets: Bool = false

    @Flag(help: "Append the raw @property attribute string as a comment.")
    var emitPropertyAttributes: Bool = false

    @Flag(help: "Append an IMP address comment after each method.")
    var emitMethodIMPAddresses: Bool = false

    @Flag(help: "Append getter and setter IMP address comments after each property.")
    var emitPropertyAccessorAddresses: Bool = false

    func build() -> ObjCGenerationOptions {
        ObjCGenerationOptions(
            stripProtocolConformance: stripProtocolConformance,
            stripOverrides: stripOverrides,
            stripSynthesizedIvars: stripSynthesizedIvars,
            stripSynthesizedMethods: stripSynthesizedMethods,
            stripCtorMethod: stripCtorMethod,
            stripDtorMethod: stripDtorMethod,
            addIvarOffsetComments: emitIvarOffsets,
            addPropertyAttributesComments: emitPropertyAttributes,
            addMethodIMPAddressComments: emitMethodIMPAddresses,
            addPropertyAccessorAddressComments: emitPropertyAccessorAddresses
        )
    }
}
