import Foundation
import DiskScopeCore
@main struct ScannerChecks {
    static func main() throws {
        try testScanAggregatesAppsAndDoesNotFollowSymlinksOrDoubleCountHardLinks()
        try testCancellation()
        testCleanupProtection()
        print("PASS: app aggregation, hard-link deduplication, symlink exclusion, cancellation, cleanup protection")
    }
    static func testScanAggregatesAppsAndDoesNotFollowSymlinksOrDoubleCountHardLinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Sample.app/Contents")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 32768).write(to: root.appendingPathComponent("large.bin"))
        try Data(repeating: 2, count: 16384).write(to: app.appendingPathComponent("payload"))
        try fm.linkItem(at: root.appendingPathComponent("large.bin"), to: root.appendingPathComponent("hardlink.bin"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let report = try StorageScanner.scan(root)
        assertEqual(report.fileCount, 2)
        assertEqual(report.files.count, 2)
        assertEqual(report.files.filter(\.isApplication).count, 1)
        precondition(report.totalBytes > 0)
        assertEqual(report.files.reduce(0) { $0 + $1.bytes }, report.totalBytes)
    }
    static func testCancellation() throws {
        do {
            _ = try StorageScanner.scan(FileManager.default.temporaryDirectory, cancelled: { true })
            preconditionFailure("Expected cancellation")
        } catch ScanFailure.cancelled {}
    }
    static func testCleanupProtection() {
        let home = URL(fileURLWithPath: "/Users/test")
        assertNotNil(CleanupSafety.reasonBlocked(URL(fileURLWithPath: "/System/a"), home: home))
        assertNotNil(CleanupSafety.reasonBlocked(home.appendingPathComponent("Library/Keychains/a"), home: home))
        assertNotNil(CleanupSafety.reasonBlocked(home.appendingPathComponent(".ssh/id_rsa"), home: home))
        assertNil(CleanupSafety.reasonBlocked(home.appendingPathComponent("Downloads/installer.iso"), home: home))
        assertNil(CleanupSafety.reasonBlocked(URL(fileURLWithPath: "/Applications/Example.app"), home: home))
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected \(a) == \(b)") }
func assertNil<T>(_ value: T?) { precondition(value == nil) }
func assertNotNil<T>(_ value: T?) { precondition(value != nil) }
