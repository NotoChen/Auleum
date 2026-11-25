import CryptoKit
import Foundation

public struct StagedUpdate: Sendable {
    public let release: UpdateRelease
    public let appURL: URL
    public let archiveURL: URL
    public let stagingDirectory: URL
    public let logURL: URL
}

/// 下载、校验并安装 GitHub Release 里的 Auleum.app。
///
/// 安全边界：只信任 HTTPS 下载到的 SHA-256 校验文件，并在替换前再校验
/// app bundle id、版本和代码签名完整性。ad-hoc 签名不能证明发布者身份，
/// 所以 SHA-256 仍是从 GitHub Release 到本地安装之间的信任锚点。
public enum UpdateInstaller {
    public static func downloadAndStage(
        _ release: UpdateRelease,
        session: URLSession = UpdateChecker.makeSession()
    ) async throws -> StagedUpdate {
        guard Paths.ensureSupportDir() else {
            throw UpdateError.notWritable(Paths.supportDir.path)
        }
        let updatesDir = Paths.updatesDir
        try FileManager.default.createDirectory(
            at: updatesDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: updatesDir.path
        )

        let root = updatesDir.appendingPathComponent(
            "v\(release.version)",
            isDirectory: true
        )
        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        let archive = root.appendingPathComponent(release.assetName)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let checksumData = try await fetch(
            release.checksumURL,
            session: session
        )
        guard let checksumText = String(data: checksumData, encoding: .utf8),
              let expected = UpdateChecksum.parse(
                checksumText,
                matching: release.assetName
              ) else {
            throw UpdateError.releaseMissingChecksum
        }

        let archiveData = try await fetch(release.assetURL, session: session)
        guard !archiveData.isEmpty else {
            throw UpdateError.downloadFailed("下载结果为空")
        }
        try archiveData.write(to: archive, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: archive.path
        )
        guard sha256(of: archive) == expected else {
            throw UpdateError.checksumMismatch
        }

        try FileManager.default.createDirectory(
            at: extracted,
            withIntermediateDirectories: true
        )
        try run(
            "/usr/bin/ditto",
            ["-x", "-k", archive.path, extracted.path]
        )

        let appURL = try locateApp(in: extracted)
        try validateBundle(appURL, expectedVersion: release.version)
        try verifySignature(appURL)

        return StagedUpdate(
            release: release,
            appURL: appURL,
            archiveURL: archive,
            stagingDirectory: root,
            logURL: Paths.updateLogURL
        )
    }

    /// 写入安装脚本并启动它。脚本会等待当前进程退出，再替换 app 并重启。
    /// 调用方返回后应当清理幕帘并调用 `NSApp.terminate(nil)`。
    @discardableResult
    public static func install(
        _ staged: StagedUpdate,
        target: URL = Bundle.main.bundleURL
    ) throws -> URL {
        guard target.pathExtension.lowercased() == "app" else {
            throw UpdateError.notWritable("目标不是 Auleum.app：\(target.path)")
        }
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable(parent.path)
        }
        guard Paths.ensureSupportDir() else {
            throw UpdateError.notWritable(Paths.supportDir.path)
        }

        let script = staged.stagingDirectory.appendingPathComponent("install.sh")
        let content = installScript(
            target: target,
            stagedApp: staged.appURL,
            logURL: staged.logURL,
            parentPID: ProcessInfo.processInfo.processIdentifier
        )
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: script.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateError.commandFailed(error.localizedDescription)
        }
        installerProcess = process
        return script
    }

    /// 删除一周前的下载/解压目录，避免 support 目录越积越大。
    public static func cleanupOldUpdates(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: Paths.updatesDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for entry in entries {
            let values = try? entry.resourceValues(
                forKeys: [.contentModificationDateKey]
            )
            if let modified = values?.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    /// 单引号安全拼接，供安装脚本使用。
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func installScript(
        target: URL,
        stagedApp: URL,
        logURL: URL,
        parentPID: Int32
    ) -> String {
        let targetPath = shellQuote(target.path)
        let stagedPath = shellQuote(stagedApp.path)
        let logPath = shellQuote(logURL.path)
        return """
        #!/bin/sh
        set -u
        TARGET=\(targetPath)
        STAGED=\(stagedPath)
        LOG=\(logPath)
        BACKUP="${TARGET}.auleum-backup"
        PARENT_PID=\(parentPID)
        exec >>"$LOG" 2>&1
        echo "=== $(date) Auleum update ==="
        echo "waiting for pid $PARENT_PID"
        while kill -0 "$PARENT_PID" 2>/dev/null; do
            sleep 0.2
        done

        if [ ! -d "$STAGED" ]; then
            echo "staged app missing: $STAGED"
            exit 1
        fi
        if [ ! -w "$(dirname "$TARGET")" ]; then
            echo "target not writable: $TARGET"
            exit 1
        fi

        rm -rf "$BACKUP"
        if [ -e "$TARGET" ]; then
            if ! mv "$TARGET" "$BACKUP"; then
                echo "could not move old app aside"
                exit 1
            fi
        fi
        if ! /usr/bin/ditto "$STAGED" "$TARGET"; then
            echo "copy failed; restoring"
            rm -rf "$TARGET"
            [ -e "$BACKUP" ] && mv "$BACKUP" "$TARGET"
            exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" >/dev/null 2>&1 || true
        if ! /usr/bin/codesign --verify --deep --strict "$TARGET"; then
            echo "signature check failed; restoring"
            rm -rf "$TARGET"
            [ -e "$BACKUP" ] && mv "$BACKUP" "$TARGET"
            /usr/bin/open "$TARGET"
            exit 1
        fi

        echo "launching updated app"
        /usr/bin/open "$TARGET"
        i=0
        while [ "$i" -lt 50 ]; do
            if /usr/bin/pgrep -f "$TARGET/Contents/MacOS/auleumd" >/dev/null 2>&1; then
                rm -rf "$BACKUP"
                echo "updated app is running"
                exit 0
            fi
            sleep 0.2
            i=$((i + 1))
        done

        echo "updated app did not start; rolling back"
        rm -rf "$TARGET"
        [ -e "$BACKUP" ] && mv "$BACKUP" "$TARGET"
        /usr/bin/open "$TARGET"
        exit 1
        """
    }

    private static var installerProcess: Process?

    private static func fetch(
        _ url: URL,
        session: URLSession
    ) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw UpdateError.httpStatus(http.statusCode)
            }
            return data
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }
    }

    private static func sha256(of url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return ""
        }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func locateApp(in directory: URL) throws -> URL {
        let direct = directory.appendingPathComponent("Auleum.app")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for entry in entries where entry.pathExtension.lowercased() == "app" {
            return entry
        }
        throw UpdateError.invalidArchive("没有找到 Auleum.app")
    }

    private static func validateBundle(
        _ app: URL,
        expectedVersion: UpdateVersion
    ) throws {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            throw UpdateError.invalidBundle("无法读取 Info.plist")
        }
        guard info["CFBundleIdentifier"] as? String
            == "io.github.notochen.auleum" else {
            throw UpdateError.invalidBundle("Bundle ID 不匹配")
        }
        guard let rawVersion = info["CFBundleShortVersionString"] as? String,
              let version = UpdateVersion(rawVersion),
              version == expectedVersion else {
            throw UpdateError.invalidBundle(
                "版本号不匹配：\(info["CFBundleShortVersionString"] ?? "unknown")"
            )
        }
    }

    private static func verifySignature(_ app: URL) throws {
        do {
            try run(
                "/usr/bin/codesign",
                ["--verify", "--deep", "--strict", app.path]
            )
        } catch {
            throw UpdateError.signatureInvalid(error.localizedDescription)
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw UpdateError.commandFailed(error.localizedDescription)
        }
        // 先读到 EOF 再等待退出，避免子进程输出超过管道缓冲区时互相阻塞。
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(
                output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
