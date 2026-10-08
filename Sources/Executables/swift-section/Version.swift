// Single source of truth for the CLI version.
// When bumping: also add Changelogs/<value>.md, set the same version in both
// AgentPlugins/swift-section/{.claude-plugin,.codex-plugin}/plugin.json, then tag the
// release with the same string.
// Verified by .github/workflows/version-check.yml (PR) and .github/workflows/release.yml (tag).
enum BundledVersion {
    static let value = "0.22.0"
}
