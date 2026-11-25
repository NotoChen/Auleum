import Foundation

public struct UpdateRelease: Equatable, Sendable {
    public let version: UpdateVersion
    public let tagName: String
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let assetName: String
    public let assetURL: URL
    public let checksumName: String
    public let checksumURL: URL
    public let publishedAt: String?

    public init(version: UpdateVersion,
                tagName: String,
                title: String,
                notes: String,
                pageURL: URL,
                assetName: String,
                assetURL: URL,
                checksumName: String,
                checksumURL: URL,
                publishedAt: String? = nil) {
        self.version = version
        self.tagName = tagName
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.assetName = assetName
        self.assetURL = assetURL
        self.checksumName = checksumName
        self.checksumURL = checksumURL
        self.publishedAt = publishedAt
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(current: UpdateVersion, latest: UpdateVersion)
    case available(UpdateRelease)
}

public enum UpdateError: Error, LocalizedError, Equatable {
    case invalidCurrentVersion(String)
    case invalidResponse
    case httpStatus(Int)
    case releaseMissingVersion
    case releaseMissingAsset
    case releaseMissingChecksum
    case checksumMismatch
    case downloadFailed(String)
    case invalidArchive(String)
    case invalidBundle(String)
    case signatureInvalid(String)
    case notWritable(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidCurrentVersion(version):
            return "当前版本号无法识别：\(version)"
        case .invalidResponse:
            return "更新服务器返回了无法识别的响应"
        case let .httpStatus(status):
            return status == 403
                ? "GitHub API 请求受限，请稍后再试"
                : "更新服务器返回 HTTP \(status)"
        case .releaseMissingVersion:
            return "Release 缺少可识别的版本号"
        case .releaseMissingAsset:
            return "Release 中没有找到 Auleum.app 的 zip 产物"
        case .releaseMissingChecksum:
            return "Release 缺少 SHA-256 校验文件，拒绝自动安装"
        case .checksumMismatch:
            return "下载文件的 SHA-256 与 Release 不一致，已停止安装"
        case let .downloadFailed(message):
            return "下载更新失败：\(message)"
        case let .invalidArchive(message):
            return "更新包无法解压或缺少 Auleum.app：\(message)"
        case let .invalidBundle(message):
            return "更新包不是有效的 Auleum 应用：\(message)"
        case let .signatureInvalid(message):
            return "更新包签名校验失败：\(message)"
        case let .notWritable(path):
            return "没有权限写入 \(path)，请把 Auleum.app 放到可写目录或以管理员方式安装"
        case let .commandFailed(message):
            return "更新命令执行失败：\(message)"
        }
    }
}

public enum UpdateChecker {
    public static let repository = "NotoChen/Auleum"
    public static let latestReleaseAPI = URL(
        string: "https://api.github.com/repos/\(repository)/releases/latest"
    )!

    /// 请求 GitHub 最新 release 并和当前版本比较。网络请求走 ephemeral session，
    /// 不读取用户浏览器的 Cookie 或网页缓存。
    public static func check(
        currentVersion: String,
        session: URLSession = makeSession()
    ) async throws -> UpdateCheckResult {
        guard let current = UpdateVersion(currentVersion) else {
            throw UpdateError.invalidCurrentVersion(currentVersion)
        }
        var request = URLRequest(url: latestReleaseAPI)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Auleum/\(currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw UpdateError.httpStatus(http.statusCode)
        }
        return try parseRelease(data: data, currentVersion: current)
    }

    /// 纯解析入口，测试和离线诊断都走这里，不依赖网络。
    public static func parseRelease(
        data: Data,
        currentVersion: UpdateVersion
    ) throws -> UpdateCheckResult {
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.invalidResponse
        }
        guard let version = UpdateVersion(release.tagName) else {
            throw UpdateError.releaseMissingVersion
        }
        let zipAssets = release.assets.filter {
            $0.name.lowercased().hasSuffix(".zip")
                && !$0.name.lowercased().contains("source")
        }
        let expectedName = "Auleum-\(version).zip"
        guard let asset = zipAssets.first(where: {
            $0.name.caseInsensitiveCompare(expectedName) == .orderedSame
        }) ?? zipAssets.first else {
            throw UpdateError.releaseMissingAsset
        }

        let checksumAssets = release.assets.filter {
            let name = $0.name.lowercased()
            return name.hasSuffix(".sha256")
                || name.hasSuffix(".sha256sums")
                || name.hasSuffix(".sha256sum")
        }
        guard let checksum = checksumAssets.first(where: {
            $0.name.caseInsensitiveCompare(asset.name + ".sha256") == .orderedSame
        }) ?? checksumAssets.first else {
            throw UpdateError.releaseMissingChecksum
        }

        let notes = (release.body ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = UpdateRelease(
            version: version,
            tagName: release.tagName,
            title: release.name?.isEmpty == false
                ? release.name!
                : "Auleum \(version)",
            notes: notes,
            pageURL: release.htmlURL,
            assetName: asset.name,
            assetURL: asset.browserDownloadURL,
            checksumName: checksum.name,
            checksumURL: checksum.browserDownloadURL,
            publishedAt: release.publishedAt
        )
        if version > currentVersion {
            return .available(parsed)
        }
        return .upToDate(current: currentVersion, latest: version)
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Auleum/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")",
        ]
        return URLSession(configuration: configuration)
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}
