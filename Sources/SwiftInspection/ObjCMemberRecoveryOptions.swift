import Foundation
import MachOKit
import MachOKitExtensions

/// The per-image knobs of the ObjC member recovery (evolution proposals
/// `objc-ancestor-override-recovery` and `objc-member-selector-recovery`) —
/// what a host may ask for beyond the two deterministic evidence tiers.
public struct ObjCMemberRecoveryOptions: Sendable, Hashable {
    /// The optional third evidence tier: an overriding ObjC method whose IMP
    /// references no Swift symbol at all — the optimizer inlined its body,
    /// leaving a bare `objc_msgSendSuper` or an outlined helper — is tied to
    /// the ONE still-unmarked member of the class whose name is the
    /// importer's spelling of its selector, so `override` prints for it. Name
    /// evidence only: the two tiers before it join, this one infers, which is
    /// why it is off by default. The dump marks members tied this way
    /// `(selector name, no symbol evidence)`.
    public var infersOverridesFromSelectorNames: Bool

    public init(infersOverridesFromSelectorNames: Bool = false) {
        self.infersOverridesFromSelectorNames = infersOverridesFromSelectorNames
    }

    /// Both tiers of joined evidence, no inference.
    public static let `default` = ObjCMemberRecoveryOptions()
}

/// The recovery options in force for each image, keyed the way every other
/// per-image store here is. `SwiftDeclarationIndexer` registers its
/// configuration's options when it prepares; `swift-section dump` registers
/// the flag it was given; a host that renders without an indexer registers
/// its own. An image nobody registered gets ``ObjCMemberRecoveryOptions/default``.
public final class ObjCMemberRecoveryOptionsStore: @unchecked Sendable {
    public static let shared = ObjCMemberRecoveryOptionsStore()

    private let lock = NSLock()
    private var optionsByImageIdentifier: [AnyHashable: ObjCMemberRecoveryOptions] = [:]

    private init() {}

    /// Installs `options` for `machO`, replacing any earlier registration.
    public func register(_ options: ObjCMemberRecoveryOptions, for machO: some MachORepresentableWithCache) {
        lock.lock()
        defer { lock.unlock() }
        optionsByImageIdentifier[AnyHashable(machO.identifier)] = options
    }

    /// The options registered for `machO`, else the default.
    public func options(for machO: some MachORepresentableWithCache) -> ObjCMemberRecoveryOptions {
        lock.lock()
        defer { lock.unlock() }
        return optionsByImageIdentifier[AnyHashable(machO.identifier)] ?? .default
    }

    public func contains(in machO: some MachORepresentableWithCache) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return optionsByImageIdentifier[AnyHashable(machO.identifier)] != nil
    }

    public func remove(for machO: some MachORepresentableWithCache) {
        lock.lock()
        defer { lock.unlock() }
        optionsByImageIdentifier[AnyHashable(machO.identifier)] = nil
    }
}
