import Foundation

public struct DiskEntry: Identifiable, Sendable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let bytes: Int64
    public let modified: Date?
    public let isApplication: Bool
    public var name: String { url.lastPathComponent }
    public init(url: URL, bytes: Int64, modified: Date? = nil, isApplication: Bool = false) {
        self.url = url; self.bytes = bytes; self.modified = modified; self.isApplication = isApplication
    }
}
public struct FolderTotal: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let bytes: Int64
}
public struct ScanReport: Sendable {
    public let root: URL
    public let files: [DiskEntry]
    public let folders: [FolderTotal]
    public let fileCount: Int
    public let totalBytes: Int64
    public let skipped: [String]
    public let elapsed: TimeInterval
}
public enum ScanFailure: Error { case cancelled; case unreadableRoot }

public enum StorageScanner {
    /// Measures allocated bytes without following symlinks or downloading cloud placeholders.
    /// Hard links are counted once; APFS clones and snapshots can still affect actual reclaimable space.
    public static func scan(_ root: URL, cancelled: @Sendable () -> Bool = { false }, progress: @Sendable (Int) -> Void = { _ in }) throws -> ScanReport {
        let start = Date()
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .fileResourceIdentifierKey]
        var skipped: [String] = []
        // Explicit traversal reports inaccessible folders and aggregates app bundles.
        var stack = [root]
        var entries: [DiskEntry] = []
        var folderBytes: [String: Int64] = [:]
        var appBytes: [URL: Int64] = [:]
        var appDates: [URL: Date] = [:]
        var seen = Set<String>()
        var total: Int64 = 0
        var count = 0
        while let directory = stack.popLast() {
            if cancelled() { throw ScanFailure.cancelled }
            let children: [URL]
            do { children = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) }
            catch {
                if directory == root { throw ScanFailure.unreadableRoot }
                if skipped.count < 200 { skipped.append(directory.path) }
                continue
            }
            for url in children {
                if cancelled() { throw ScanFailure.cancelled }
                do {
                    let v = try url.resourceValues(forKeys: Set(keys))
                    if v.isSymbolicLink == true { continue }
                    if v.isUbiquitousItem == true, let status = v.ubiquitousItemDownloadingStatus, status == .notDownloaded { continue }
                    if v.isDirectory == true {
                        if url.lastPathComponent == ".Trash" { continue }
                        stack.append(url)
                        if url.pathExtension.lowercased() == "app" { appBytes[url] = appBytes[url] ?? 0; appDates[url] = v.contentModificationDate }
                        continue
                    }
                    guard v.isRegularFile == true else { continue }
                    // Device/inode from lstat identifies hard links and avoids counting them twice.
                    let attrs = try fm.attributesOfItem(atPath: url.path)
                    let identity = "\(attrs[.systemNumber] ?? 0)-\(attrs[.systemFileNumber] ?? 0)"
                    guard seen.insert(identity).inserted else { continue }
                    let bytes = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                    count += 1; total += bytes
                    let relative = url.path.dropFirst(root.path.hasSuffix("/") ? root.path.count : root.path.count + 1)
                    let top = relative.split(separator: "/").first.map(String.init) ?? "Other"
                    folderBytes[top, default: 0] += bytes
                    var parent = url.deletingLastPathComponent()
                    var app: URL?
                    while parent.path != root.path && parent.path != "/" {
                        if parent.pathExtension.lowercased() == "app" { app = parent }
                        parent.deleteLastPathComponent()
                    }
                    if let app { appBytes[app, default: 0] += bytes }
                    else { entries.append(DiskEntry(url: url, bytes: bytes, modified: v.contentModificationDate)) }
                    if count % 500 == 0 { progress(count) }
                } catch {
                    if skipped.count < 200 { skipped.append(url.path) }
                }
            }
        }
        entries += appBytes.map { DiskEntry(url: $0.key, bytes: $0.value, modified: appDates[$0.key], isApplication: true) }
        return ScanReport(root: root, files: entries.sorted { $0.bytes > $1.bytes },
            folders: folderBytes.map { FolderTotal(name: $0.key, bytes: $0.value) }.sorted { $0.bytes > $1.bytes },
            fileCount: count, totalBytes: total, skipped: skipped, elapsed: Date().timeIntervalSince(start))
    }
}

public enum CleanupSafety {
    public static func reasonBlocked(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let path = url.standardizedFileURL.path
        if url.standardizedFileURL.resolvingSymlinksInPath().path != path { return "Symbolic-link locations are review-only." }
        if path == home.path || path == "/" || path == "/Applications" { return "Top-level folders cannot be removed." }
        if ["/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/Volumes"].contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return "Protected system location." }
        if path.hasPrefix(home.path + "/Library/") { return "App and system data is review-only. Use the owning app to manage it." }
        if path.hasPrefix(home.path + "/.") { return "Hidden configuration is review-only." }
        guard path.hasPrefix(home.path + "/") || (path.hasPrefix("/Applications/") && url.pathExtension.lowercased() == "app") else { return "Cleanup is limited to your files and installed apps." }
        return nil
    }
}
