// Single source of truth for the CLI version.
// When bumping: also add Changelogs/<value>.md, then tag the release with the same string.
// Verified by .github/workflows/version-check.yml (PR) and .github/workflows/release.yml (tag).
enum BundledVersion {
    static let value = "0.10.1"
}
