import Foundation
import Testing
@testable import AuleumKit

@Suite("Updates")
struct UpdateTests {
    @Test("Versions normalize v prefix and trailing zeros")
    func versionNormalization() throws {
        let one = try #require(UpdateVersion("v0.0.1"))
        let same = try #require(UpdateVersion("0.0.1.0"))
        #expect(one == same)
        #expect(one.description == "0.0.1")
        #expect(UpdateVersion("dev") == nil)
        #expect(UpdateVersion("1.2") == UpdateVersion("1.2.0"))
    }

    @Test("Versions compare numerically and honor prereleases")
    func versionOrdering() throws {
        let older = try #require(UpdateVersion("0.0.1"))
        let newer = try #require(UpdateVersion("0.0.2"))
        let beta = try #require(UpdateVersion("1.0.0-beta.2"))
        let release = try #require(UpdateVersion("1.0.0"))
        let betaOne = try #require(UpdateVersion("1.0.0-beta.1"))

        #expect(older < newer)
        #expect(betaOne < beta)
        #expect(beta < release)
    }

    @Test("Checksum files accept plain and starred filenames")
    func checksumParsing() {
        let hash = String(repeating: "a", count: 64)
        let text = """
        \(hash)  Auleum-0.0.1.zip
        \(String(repeating: "b", count: 64)) *Auleum-0.0.1.dmg
        """
        #expect(
            UpdateChecksum.parse(text, matching: "Auleum-0.0.1.zip")
                == hash
        )
        #expect(
            UpdateChecksum.parse(text, matching: "Auleum-0.0.1.dmg")
                == String(repeating: "b", count: 64)
        )
        #expect(
            UpdateChecksum.parse(text, matching: "Auleum-0.0.2.zip") == nil
        )
    }

    @Test("Release parsing selects the zip and checksum assets")
    func releaseParsing() throws {
        let data = Data(Self.releaseJSON.utf8)
        let current = try #require(UpdateVersion("0.0.1"))
        let result = try UpdateChecker.parseRelease(
            data: data,
            currentVersion: current
        )
        guard case let .available(release) = result else {
            Issue.record("Expected an available update")
            return
        }
        #expect(release.version == UpdateVersion("0.0.2"))
        #expect(release.assetName == "Auleum-0.0.2.zip")
        #expect(release.checksumName == "Auleum-0.0.2.SHA256SUMS")
        #expect(release.notes == "Release notes")
    }

    @Test("Equal and older releases are up to date")
    func upToDate() throws {
        let data = Data(Self.releaseJSON.utf8)
        let current = try #require(UpdateVersion("0.0.2"))
        let result = try UpdateChecker.parseRelease(
            data: data,
            currentVersion: current
        )
        guard case let .upToDate(latestCurrent, latest) = result else {
            Issue.record("Expected an up-to-date result")
            return
        }
        #expect(latestCurrent == current)
        #expect(latest == UpdateVersion("0.0.2"))
    }

    @Test("Release without checksum is rejected")
    func missingChecksum() throws {
        let json = Self.releaseJSON.replacingOccurrences(
            of: """
            ,
                {
                  "name": "Auleum-0.0.2.SHA256SUMS",
                  "browser_download_url": "https://example.com/Auleum-0.0.2.SHA256SUMS"
                }
            """,
            with: ""
        )
        let current = try #require(UpdateVersion("0.0.1"))
        #expect(throws: UpdateError.releaseMissingChecksum) {
            _ = try UpdateChecker.parseRelease(
                data: Data(json.utf8),
                currentVersion: current
            )
        }
    }

    @Test("Shell quoting keeps install paths safe")
    func shellQuoting() {
        #expect(UpdateInstaller.shellQuote("/Applications/Auleum.app") ==
            "'/Applications/Auleum.app'")
        #expect(UpdateInstaller.shellQuote("a'b") == "'a'\\''b'")
    }

    private static let releaseJSON = """
    {
      "tag_name": "v0.0.2",
      "name": "Auleum 0.0.2",
      "body": "Release notes",
      "html_url": "https://github.com/NotoChen/Auleum/releases/tag/v0.0.2",
      "published_at": "2026-11-25T12:00:00Z",
      "assets": [
        {
          "name": "Auleum-0.0.2.zip",
          "browser_download_url": "https://example.com/Auleum-0.0.2.zip"
        },
        {
          "name": "Auleum-0.0.2.SHA256SUMS",
          "browser_download_url": "https://example.com/Auleum-0.0.2.SHA256SUMS"
        }
      ]
    }
    """
}
