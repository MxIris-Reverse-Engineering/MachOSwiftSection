/// One identity-key collision the first-wins keying resolved silently: two
/// records in the same keying scope (one container's members, one global
/// bucket, or one container axis) carried the same identity, so only the
/// first was compared and the rest were dropped.
///
/// A dropped record can hide a change — most realistically a removal
/// classified as compatible. The one known-legitimate source is the merged
/// extension bucket: two conditional extensions (`where T: P` vs `where T: Q`)
/// each declaring a member whose mangling does not encode the `where` clause
/// collide once their members are flattened into one bucket (see
/// `Documentations/Internal/ABIDiffDesignAndLimitations.md`).
public struct ABIKeyCollision: Sendable, Codable, Equatable {
    /// The identity that collided.
    public let key: ABIKey
    /// The owning container's reporting name; `nil` for a global bucket or a
    /// container-level collision.
    public let containerName: String?
    /// Human-readable renderings of the records that were dropped (the first
    /// record with the key was kept and compared).
    public let droppedSignatures: [String]

    public init(key: ABIKey, containerName: String?, droppedSignatures: [String]) {
        self.key = key
        self.containerName = containerName
        self.droppedSignatures = droppedSignatures
    }
}

/// One record whose key came from the remangle-fallback path (`unmangled:`
/// prefix — the node failed `mangleAsString` and was keyed by its printed
/// text instead).
///
/// Behaviorally benign on its own: the fallback is deterministic, so two
/// sides presenting the same node still match. The risk it flags is
/// cross-toolchain comparison, where structurally different demangle trees
/// can remangle on one side and throw on the other, flipping the identity
/// `.mangled`↔`.printed` and surfacing the declaration as removed+added (see
/// `ABIKey.make(for:)`). Surfaced so that story is observable, not silent.
public struct ABIRemangleFallback: Sendable, Codable, Equatable {
    /// The fallback-carrying key (a member's identity/payload key, or a
    /// container key embedding a fallback component).
    public let key: ABIKey
    /// The owning container's reporting name; `nil` for a container-level key
    /// or a global bucket.
    public let containerName: String?
    /// Human-readable rendering of the affected record (a member's signature,
    /// or the container's name).
    public let signature: String

    public init(key: ABIKey, containerName: String?, signature: String) {
        self.key = key
        self.containerName = containerName
        self.signature = signature
    }
}

/// The diagnostics side-channel of an `ABIDiff`: everything the comparison
/// had to resolve silently, surfaced so a verdict is never quietly weaker
/// than it looks. `nil` on the diff when there is nothing to report.
public struct ABIDiffDiagnostics: Sendable, Codable, Equatable {
    /// Collisions found while keying the old side's snapshot.
    public let oldSideKeyCollisions: [ABIKeyCollision]
    /// Collisions found while keying the new side's snapshot.
    public let newSideKeyCollisions: [ABIKeyCollision]
    /// Remangle-fallback keys found in the old side's snapshot.
    public let oldSideRemangleFallbacks: [ABIRemangleFallback]
    /// Remangle-fallback keys found in the new side's snapshot.
    public let newSideRemangleFallbacks: [ABIRemangleFallback]

    public init(
        oldSideKeyCollisions: [ABIKeyCollision],
        newSideKeyCollisions: [ABIKeyCollision],
        oldSideRemangleFallbacks: [ABIRemangleFallback] = [],
        newSideRemangleFallbacks: [ABIRemangleFallback] = []
    ) {
        self.oldSideKeyCollisions = oldSideKeyCollisions
        self.newSideKeyCollisions = newSideKeyCollisions
        self.oldSideRemangleFallbacks = oldSideRemangleFallbacks
        self.newSideRemangleFallbacks = newSideRemangleFallbacks
    }

    public var isEmpty: Bool {
        oldSideKeyCollisions.isEmpty && newSideKeyCollisions.isEmpty
            && oldSideRemangleFallbacks.isEmpty && newSideRemangleFallbacks.isEmpty
    }
}

extension ABISnapshot {
    /// Every identity-key collision the first-wins keying would silently
    /// resolve when this snapshot is diffed: duplicate container keys within
    /// one axis, and duplicate member identities within one container or
    /// global bucket. Deterministically ordered (container name, then key).
    public func keyCollisions() -> [ABIKeyCollision] {
        var collisions: [ABIKeyCollision] = []
        for axis in [types, protocols, typeExtensions, protocolExtensions, typeAliasExtensions, conformanceExtensions] {
            collectContainerKeyCollisions(axis, into: &collisions)
            for container in axis {
                collectMemberKeyCollisions(container.members, containerName: container.name, into: &collisions)
            }
        }
        collectMemberKeyCollisions(globalVariables, containerName: nil, into: &collisions)
        collectMemberKeyCollisions(globalFunctions, containerName: nil, into: &collisions)
        return collisions.sorted {
            ($0.containerName ?? "", $0.key.sortKey) < ($1.containerName ?? "", $1.key.sortKey)
        }
    }

    /// Two containers with the same key on one axis (dropped ones surface by
    /// name — a container has no signature).
    private func collectContainerKeyCollisions(_ containers: [ContainerSnapshot], into collisions: inout [ABIKeyCollision]) {
        var firstSeen: Set<ABIKey> = []
        var droppedNamesByKey: [ABIKey: [String]] = [:]
        for container in containers {
            if firstSeen.contains(container.key) {
                droppedNamesByKey[container.key, default: []].append(container.name)
            } else {
                firstSeen.insert(container.key)
            }
        }
        for (key, droppedNames) in droppedNamesByKey {
            collisions.append(ABIKeyCollision(key: key, containerName: nil, droppedSignatures: droppedNames))
        }
    }

    private func collectMemberKeyCollisions(_ members: [MemberRecord], containerName: String?, into collisions: inout [ABIKeyCollision]) {
        var firstSeen: Set<ABIKey> = []
        var droppedSignaturesByKey: [ABIKey: [String]] = [:]
        for member in members {
            if firstSeen.contains(member.identityKey) {
                droppedSignaturesByKey[member.identityKey, default: []].append(member.signature)
            } else {
                firstSeen.insert(member.identityKey)
            }
        }
        for (key, droppedSignatures) in droppedSignaturesByKey {
            collisions.append(ABIKeyCollision(key: key, containerName: containerName, droppedSignatures: droppedSignatures))
        }
    }

    /// Every remangle-fallback key in this snapshot: container keys (including
    /// composed `extbucket:` keys embedding a fallback component) and member
    /// identity/payload keys, across all axes and the global buckets. One
    /// entry per affected record (identity preferred over payload when both
    /// fell back). Deterministically ordered (container name, then key).
    public func remangleFallbacks() -> [ABIRemangleFallback] {
        var fallbacks: [ABIRemangleFallback] = []
        for axis in [types, protocols, typeExtensions, protocolExtensions, typeAliasExtensions, conformanceExtensions] {
            for container in axis {
                if container.key.isRemangleFallback {
                    fallbacks.append(ABIRemangleFallback(key: container.key, containerName: nil, signature: container.name))
                }
                collectMemberRemangleFallbacks(container.members, containerName: container.name, into: &fallbacks)
            }
        }
        collectMemberRemangleFallbacks(globalVariables, containerName: nil, into: &fallbacks)
        collectMemberRemangleFallbacks(globalFunctions, containerName: nil, into: &fallbacks)
        return fallbacks.sorted {
            ($0.containerName ?? "", $0.key.sortKey) < ($1.containerName ?? "", $1.key.sortKey)
        }
    }

    private func collectMemberRemangleFallbacks(_ members: [MemberRecord], containerName: String?, into fallbacks: inout [ABIRemangleFallback]) {
        for member in members {
            if member.identityKey.isRemangleFallback {
                fallbacks.append(ABIRemangleFallback(key: member.identityKey, containerName: containerName, signature: member.signature))
            } else if member.payloadKey.isRemangleFallback {
                fallbacks.append(ABIRemangleFallback(key: member.payloadKey, containerName: containerName, signature: member.signature))
            }
        }
    }
}
