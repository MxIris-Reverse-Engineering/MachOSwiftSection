import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// The public face of the ObjC member recovery (evolution proposals
/// `objc-ancestor-override-recovery` and `objc-member-selector-recovery`):
/// per class, every entry of its ObjC method table tied to the Swift member
/// implementing it — which is the class's `@objc` member list, the
/// `override` facts (an entry whose selector an ancestor also implements)
/// and the explicit selectors (an entry whose selector is not what the
/// compiler derives from the Swift name) in one table. The hierarchy comes
/// from the host's registered `ObjCClassHierarchyProviding` when there is
/// one, else from the library's own reader; the join to Swift symbols is
/// the same either way, in two tiers of evidence — the `To` thunk symbol at
/// the IMP, or (stripped) the Swift implementation the IMP's code
/// references, guarded by the selector being the importer's spelling of the
/// member's name — plus an optional third, name-only tier for overrides
/// that is off by default.
///
/// Lives in `SwiftThunkAnalysis` rather than next to the hierarchy in
/// `SwiftInspection` because the second tier decodes the thunk, and the
/// decoder sits here, above `SwiftInspection`.
@Loggable(.private, subsystem: "com.machoswiftsection.swift-thunk-analysis", category: "ObjCMembers")
public enum ObjCMembers {
    /// Whether an overriding ObjC method whose IMP ties to no Swift symbol at
    /// all (an inlined body) is attributed to the one member of the class
    /// whose name is the importer's spelling of its selector. Off by default:
    /// the recovery joins, it does not guess — turn it on to also mark the
    /// overrides an OS framework's optimizer inlined away.
    public static var infersOverridesFromSelectorNames: Bool {
        get {
            inferenceSwitchLock.lock()
            defer { inferenceSwitchLock.unlock() }
            return inferenceSwitchValue
        }
        set {
            inferenceSwitchLock.lock()
            defer { inferenceSwitchLock.unlock() }
            inferenceSwitchValue = newValue
        }
    }

    // `NSLock`, not `OSAllocatedUnfairLock`: the package deploys to macOS 10.15.
    private static let inferenceSwitchLock = NSLock()
    nonisolated(unsafe) private static var inferenceSwitchValue = false

    /// The table for the class the image defines under ObjC runtime name
    /// `runtimeName` — a bare name for an ObjC-declared class such as an
    /// `@objc @implementation` one — or for the image's categories on a
    /// class another image defines (a Swift `extension NSView` with `@objc`
    /// members). `nil` when the image has neither, or no ObjC method to tie.
    public static func table(forObjCClassNamed runtimeName: String, in machO: some MachORepresentableWithCache) -> ObjCMemberTable? {
        guard let hierarchy = hierarchy(forClassNamed: runtimeName, in: machO) else { return nil }
        // An `@objc @implementation` body is no exception to the derivation:
        // the compiler derives the selector from the member's Swift name and
        // demands that the header declare it (`draw(in:)` → `drawIn:` is
        // rejected against a header saying `drawInRect:`), so a header
        // selector the derivation does not produce means the Swift source
        // wrote `@objc(drawInRect:)` — exactly what the flag reports.
        return table(for: hierarchy, ownerQualifiedName: "\(objcModule).\(runtimeName)", in: machO)
    }

    /// The table for the Swift class whose qualified name is `qualifiedName`
    /// (`SwiftUI.SliderMarkLabels.CustomMarkedSliderCell` — the same key the
    /// static layout engine uses). `nil` when the image has no static class
    /// object for it (a generic class), or when several same-named private
    /// classes make the name ambiguous.
    public static func table(forSwiftClassQualifiedName qualifiedName: String, in machO: some MachORepresentableWithCache) -> ObjCMemberTable? {
        let runtimeNames = ObjCClassMethodIndex.shared.runtimeNames(forSwiftClassQualifiedName: qualifiedName, in: machO)
        guard let runtimeName = runtimeNames.first else { return nil }
        guard runtimeNames.count == 1 else {
            #log(.info, "\(runtimeNames.count) class objects print as \(qualifiedName, privacy: .public); not attributing ObjC members to any of them")
            return nil
        }
        guard let hierarchy = hierarchy(forClassNamed: runtimeName, in: machO) else { return nil }
        return table(for: hierarchy, ownerQualifiedName: qualifiedName, in: machO)
    }

    private static func hierarchy(forClassNamed runtimeName: String, in machO: some MachORepresentableWithCache) -> ObjCClassHierarchy? {
        if let provider = ObjCClassHierarchyProviderStore.shared.provider(for: machO), let hierarchy = provider.objcClassHierarchy(forClassNamed: runtimeName) {
            return hierarchy
        }
        return ObjCClassMethodIndex.shared.hierarchy(forRuntimeName: runtimeName, in: machO)
    }

    private static func table(for hierarchy: ObjCClassHierarchy, ownerQualifiedName: String, in machO: some MachORepresentableWithCache) -> ObjCMemberTable {
        var members: [String: ObjCMember] = [:]
        var unattributed: [ObjCMemberTable.UnattributedMethod] = []
        // An inherited selector can be ruled out only when every source of
        // one was read: the whole ancestor chain and every protocol the class
        // or an ancestor adopts (a conformance is inherited).
        // A standalone file's superclass or SDK protocol is a bind with
        // nothing behind it, and there every override of a UIKit method
        // (`hitTest:withEvent:` for `hitTest(_:with:)`) would otherwise pass
        // for an `@objc(name)` — so nothing is claimed; the dump still shows
        // the selector, only the verdict is withheld.
        let canRuleOutInheritance = hierarchy.isAncestorChainComplete && hierarchy.isAdoptedProtocolSetComplete
        for method in hierarchy.methods {
            let ancestor = hierarchy.ancestorDeclaring(selector: method.selector, isClassMethod: method.isClassMethod)
            let isWitness = hierarchy.adoptedProtocolDeclares(selector: method.selector, isClassMethod: method.isClassMethod)
            func member(evidence: ObjCMember.Evidence, shape: ObjCMemberShape?) -> ObjCMember {
                ObjCMember(
                    className: hierarchy.className,
                    selector: method.selector,
                    isClassMethod: method.isClassMethod,
                    overriddenAncestorClassName: ancestor?.className,
                    evidence: evidence,
                    hasExplicitSelector: canRuleOutInheritance && hasExplicitSelector(shape, selector: method.selector, isOverride: ancestor != nil, isWitness: isWitness)
                )
            }
            let offset: Int? = switch method.implementation {
            case .offset(let offset): offset
            case .address(let address): machO.resolveOffset(at: address)
            case nil: nil
            }
            var isAttributed = false
            if let offset {
                // Tier 1: the member's own `To` thunk sits at the IMP.
                // `symbols(offset:)` already filters to Swift symbols.
                if let symbols = machO.symbols(offset: offset), !symbols.isEmpty {
                    // Identical code folding can put several members' thunks
                    // at one address; the ones whose shape fits the selector
                    // are this method's, the rest belong to other entries.
                    var shapesBySymbolName: [String: ObjCMemberShape?] = [:]
                    for symbol in symbols {
                        shapesBySymbolName[symbol.name] = (try? demangleAsNodeTransient(symbol.name)).flatMap { ObjCMemberShape(demangledSymbol: $0) }
                    }
                    let consistentNames = shapesBySymbolName.filter { $0.value?.isConsistent(withSelector: method.selector, isClassMethod: method.isClassMethod) ?? false }.map(\.key)
                    let attributedNames = consistentNames.isEmpty ? Array(shapesBySymbolName.keys) : consistentNames
                    for symbolName in attributedNames {
                        members[symbolName] = member(evidence: .thunkSymbol, shape: shapesBySymbolName[symbolName] ?? nil)
                    }
                    isAttributed = true
                } else {
                    // Tier 2: the anonymous thunk's code references the
                    // implementation. Guarded twice — the symbol must be a
                    // member of THIS class and its name the importer's
                    // spelling of the selector — because an inlined body
                    // references whatever it calls.
                    for symbolName in ObjCMethodThunkReferences.referencedSwiftSymbolNames(atImplementationOffset: offset, in: machO) {
                        guard let root = try? demangleAsNodeTransient(symbolName),
                              let shape = ObjCMemberShape(demangledSymbol: root),
                              shape.ownerQualifiedName == ownerQualifiedName,
                              shape.isConsistent(withSelector: method.selector, isClassMethod: method.isClassMethod)
                        else { continue }
                        members[symbolName] = member(evidence: .thunkReference, shape: shape)
                        isAttributed = true
                    }
                }
            }
            if !isAttributed {
                unattributed.append(.init(selector: method.selector, isClassMethod: method.isClassMethod, overriddenAncestorClassName: ancestor?.className))
            }
        }
        return ObjCMemberTable(hierarchy: hierarchy, membersByImplementationSymbolName: members, unattributedMethods: unattributed)
    }

    /// An explicit `@objc(name)` shows as a selector the compiler would not
    /// have derived from the Swift name — unless the selector was inherited:
    /// an override takes the overridden member's, a witness the requirement's.
    /// With no shape to derive from (a symbol of an unexpected form) nothing
    /// is claimed. The caller has already established that inheritance CAN
    /// be ruled out (chain and protocols fully read).
    private static func hasExplicitSelector(_ shape: ObjCMemberShape?, selector: String, isOverride: Bool, isWitness: Bool) -> Bool {
        guard !isOverride, !isWitness, let shape else { return false }
        return !shape.isDefaultSelector(selector)
    }
}
