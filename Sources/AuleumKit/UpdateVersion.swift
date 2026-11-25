import Foundation

/// 发布版本号。只接受数字点分版本，可选 `v` 前缀和 semver 预发布后缀。
public struct UpdateVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]
    public let prerelease: [String]?

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("v") {
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }
        if let build = text.firstIndex(of: "+") {
            text = String(text[..<build])
        }
        let pieces = text.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let numeric = pieces[0].split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard !numeric.isEmpty else { return nil }

        var numbers: [Int] = []
        for part in numeric {
            guard !part.isEmpty,
                  let value = Int(part),
                  value >= 0 else {
                return nil
            }
            numbers.append(value)
        }
        components = numbers
        if pieces.count == 2, !pieces[1].isEmpty {
            prerelease = pieces[1].split(separator: ".").map(String.init)
        } else {
            prerelease = nil
        }
    }

    public var description: String {
        let base = components.map(String.init).joined(separator: ".")
        guard let prerelease, !prerelease.isEmpty else { return base }
        return "\(base)-\(prerelease.joined(separator: "."))"
    }

    public static func == (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        lhs.compare(to: rhs) == 0
    }

    public static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        lhs.compare(to: rhs) < 0
    }

    private func compare(to other: UpdateVersion) -> Int {
        let count = max(components.count, other.components.count)
        for index in 0..<count {
            let left = index < components.count ? components[index] : 0
            let right = index < other.components.count
                ? other.components[index]
                : 0
            if left != right {
                return left < right ? -1 : 1
            }
        }

        switch (prerelease, other.prerelease) {
        case (nil, nil):
            return 0
        case (nil, _):
            return 1
        case (_, nil):
            return -1
        case let (left?, right?):
            for (a, b) in zip(left, right) where a != b {
                let leftNumber = Int(a)
                let rightNumber = Int(b)
                if let leftNumber, let rightNumber {
                    return leftNumber < rightNumber ? -1 : 1
                }
                if leftNumber != nil { return -1 }
                if rightNumber != nil { return 1 }
                return a < b ? -1 : 1
            }
            if left.count == right.count { return 0 }
            return left.count < right.count ? -1 : 1
        }
    }
}

/// 发布资产里的 SHA-256 清单。支持 `hash  filename`、`hash *filename`。
public enum UpdateChecksum {
    public static func parse(_ text: String, matching filename: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            let hash = String(fields[0]).lowercased()
            guard hash.count == 64,
                  hash.allSatisfy(\.isHexDigit) else {
                continue
            }
            var name = String(fields[1])
            if name.hasPrefix("*") {
                name.removeFirst()
            }
            let base = URL(fileURLWithPath: name).lastPathComponent
            if base == filename {
                return hash
            }
        }
        return nil
    }
}
