import SwiftUI
import AppKit
import DiskScopeCore

func size(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .binary) }

@MainActor @Observable final class DiskModel {
    var report: ScanReport?
    var scanning = false
    var count = 0
    var selection = Set<String>()
    var query = ""
    var removedIDs = Set<String>()
    var appsOnly = false
    var message = ""
    var errors: [String] = []
    var capacity: Int64 = 0
    var available: Int64 = 0
    private var task: Task<Void, Never>?
    var selected: [DiskEntry] { report?.files.filter { selection.contains($0.id) } ?? [] }
    var filtered: [DiskEntry] {
        (report?.files ?? []).filter { (!removedIDs.contains($0.id)) && (!appsOnly || $0.isApplication) && (query.isEmpty || $0.url.path.localizedCaseInsensitiveContains(query)) }
    }
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to analyze. No files are modified during a scan."
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }
    func scan(_ url: URL) {
        guard !scanning else { return }
        scanning = true; count = 0; selection = []; removedIDs = []; errors = []; message = ""
        let volume = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        capacity = Int64(volume?.volumeTotalCapacity ?? 0); available = Int64(volume?.volumeAvailableCapacity ?? 0)
        task = Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    try StorageScanner.scan(url, cancelled: { Task.isCancelled }, progress: { _ in })
                }.value
                if !Task.isCancelled { report = result; count = result.fileCount }
            } catch { message = "Could not scan this folder. Check macOS Files & Folders permissions and try again." }
            scanning = false
        }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func trashSelected() {
        errors = []
        var moved = 0
        for entry in selected {
            if let reason = CleanupSafety.reasonBlocked(entry.url) { errors.append("\(entry.name): \(reason)"); continue }
            do {
                // Revalidate at action time; do not follow symlinks or stale selections.
                let v = try entry.url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                if v.isSymbolicLink == true { errors.append("\(entry.name): changed to a symbolic link; skipped."); continue }
                if v.isDirectory == true && !entry.isApplication { errors.append("\(entry.name): folders are review-only."); continue }
                var result: NSURL?
                try FileManager.default.trashItem(at: entry.url, resultingItemURL: &result)
                moved += 1
            } catch { errors.append("\(entry.name): \(error.localizedDescription)") }
        }
        message = "Moved \(moved) item\(moved == 1 ? "" : "s") to Trash. Empty Trash in Finder to reclaim space."
        removedIDs.formUnion(selected.filter { !FileManager.default.fileExists(atPath: $0.url.path) }.map(\.id))
        selection = []
    }
}
@main struct DiskScopeApp: App {
    @State private var model = DiskModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
                .preferredColorScheme(.dark)
        }.defaultSize(width: 1180, height: 800)
    }
}

struct ContentView: View {
    @Bindable var model: DiskModel
    @State private var review = false
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Image(systemName: "externaldrive.fill").foregroundStyle(.mint); Text("DiskScope").font(.title2.bold()) }
                Text("KNOW YOUR SPACE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Button { model.choose() } label: { Label("Choose folder", systemImage: "folder.badge.plus") }.buttonStyle(.borderedProminent).tint(.mint).disabled(model.scanning)
                VStack(alignment: .leading, spacing: 14) {
                    Text("QUICK SCANS").font(.caption).foregroundStyle(.secondary)
                    quick("Applications", "square.stack.3d.up", URL(fileURLWithPath: "/Applications"))
                    quick("Home folder", "house", FileManager.default.homeDirectoryForCurrentUser)
                    quick("Downloads", "arrow.down.circle", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                }
                Spacer()
                Label("Local and private", systemImage: "lock.shield").font(.subheadline).foregroundStyle(.mint)
                Text("Scans stay on this Mac.\nNothing is deleted automatically.").font(.caption).foregroundStyle(.secondary)
            }.padding(26).frame(width: 225).frame(maxHeight: .infinity).background(Color(red: 0.065, green: 0.09, blue: 0.12))
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Make room for what matters.").font(.system(size: 28, weight: .semibold))
                        Text(model.report?.root.path ?? "Choose a folder to see where your storage goes.").font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    if let report = model.report { Button { model.scan(report.root) } label: { Label("Rescan", systemImage: "arrow.clockwise") }.disabled(model.scanning) }
                }
                if model.scanning {
                    HStack { ProgressView().controlSize(.small); Text("Scanning allocated storage… You can keep using your Mac.").foregroundStyle(.secondary) }.padding()
                }
                if let report = model.report {
                    HStack(spacing: 12) {
                        metric("SCANNED DATA", size(report.totalBytes), "Allocated bytes at last scan", "chart.bar.fill")
                        metric("FILES SCANNED", report.fileCount.formatted(), String(format: "Completed in %.1f seconds", report.elapsed), "doc.on.doc")
                        metric("VOLUME FREE", size(model.available), "Of \(size(model.capacity)) total", "internaldrive")
                    }
                    if !report.skipped.isEmpty {
                        DisclosureGroup("Partial scan · \(report.skipped.count) inaccessible paths recorded (up to 200)") {
                            Text("macOS may require Files & Folders or Full Disk Access for protected data. Grant access only if you want to include it, then rescan.").font(.caption).foregroundStyle(.secondary)
                            ScrollView { Text(report.skipped.joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
                        }.padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Where it goes").font(.headline)
                            ForEach(Array(report.folders.prefix(6))) { folder in
                                HStack {
                                    Text(folder.name).lineLimit(1).frame(width: 130, alignment: .leading)
                                    GeometryReader { geo in
                                        Capsule().fill(.mint.opacity(0.16)).overlay(alignment: .leading) {
                                            Capsule().fill(.mint).frame(width: max(2, geo.size.width * Double(folder.bytes) / Double(max(1, report.folders.first?.bytes ?? 1))))
                                        }
                                    }.frame(height: 6)
                                    Text(size(folder.bytes)).monospacedDigit().frame(width: 90, alignment: .trailing)
                                }.font(.caption)
                            }
                        }.padding(16).frame(maxWidth: .infinity).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        Text("Largest items").font(.headline)
                        Text("\(model.filtered.count.formatted()) results").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Apps only", isOn: $model.appsOnly).toggleStyle(.checkbox)
                        TextField("Search name or path", text: $model.query).textFieldStyle(.roundedBorder).frame(width: 220)
                    }
                    Table(model.filtered, selection: $model.selection) {
                        TableColumn("Name") { item in
                            HStack { Image(systemName: item.isApplication ? "app.fill" : "doc.fill").foregroundStyle(.mint); Text(item.name).lineLimit(1) }.help(item.url.path)
                        }.width(min: 190, ideal: 270)
                        TableColumn("On disk") { item in Text(size(item.bytes)).monospacedDigit() }.width(95)
                        TableColumn("Location") { item in Text(item.url.deletingLastPathComponent().path).foregroundStyle(.secondary).lineLimit(1).help(item.url.path) }
                        TableColumn("Action") { item in Button("Show") { model.reveal(item.url) }.buttonStyle(.borderless) }.width(50)
                    }.contextMenu(forSelectionType: String.self) { ids in
                        if let id = ids.first, let item = report.files.first(where: { $0.id == id }) { Button("Reveal in Finder") { model.reveal(item.url) } }
                    }
                    HStack {
                        Text("Allocated bytes; APFS sharing means freed space may differ. Rescan after cleanup.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Review \(model.selected.count) selected") { review = true }.buttonStyle(.borderedProminent).tint(.mint).disabled(model.selected.isEmpty || model.scanning)
                    }
                } else if !model.scanning {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "chart.pie.fill").font(.system(size: 64)).foregroundStyle(.mint.gradient)
                        Text("A clearer view of your Mac.").font(.title2.bold())
                        Text("Find large files and apps. Review every item before moving it to Trash.").foregroundStyle(.secondary)
                        Button("Start with Applications") { model.scan(URL(fileURLWithPath: "/Applications")) }.buttonStyle(.borderedProminent).tint(.mint)
                    }.frame(maxWidth: .infinity)
                    Spacer()
                }
                if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(.mint).textSelection(.enabled) }
                if !model.errors.isEmpty { Text(model.errors.joined(separator: "\n")).font(.caption).foregroundStyle(.orange).lineLimit(4) }
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.04, green: 0.055, blue: 0.075))
        }.sheet(isPresented: $review) { ReviewView(model: model) }
    }
    func quick(_ title: String, _ icon: String, _ url: URL) -> some View {
        Button { model.scan(url) } label: { Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).disabled(model.scanning)
    }
    func metric(_ title: String, _ value: String, _ detail: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(.mint) }
            Text(value).font(.system(size: 27, weight: .semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ReviewView: View {
    @Bindable var model: DiskModel
    @Environment(\.dismiss) var dismiss
    @State private var confirmed = false
    var eligible: [DiskEntry] { model.selected.filter { CleanupSafety.reasonBlocked($0.url) == nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review before cleanup").font(.title2.bold())
            Text("Eligible items will move to Finder’s Trash. You can restore them there. DiskScope never empties Trash. Removing cloud-synced files may also remove their synced copies. Quit an app before removing its bundle.").foregroundStyle(.secondary)
            List(model.selected) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(item.name).fontWeight(.medium); Spacer(); Text(size(item.bytes)) }
                    Text(item.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let reason = CleanupSafety.reasonBlocked(item.url) { Label(reason, systemImage: "lock.fill").font(.caption).foregroundStyle(.orange) }
                }.padding(.vertical, 5)
            }.frame(height: 260)
            Text("\(eligible.count) eligible items · \(size(eligible.reduce(0) { $0 + $1.bytes })) measured on disk").font(.headline)
            Toggle("I reviewed the paths and no longer need these items.", isOn: $confirmed)
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Move eligible items to Trash") { model.trashSelected(); dismiss() }.disabled(!confirmed || eligible.isEmpty).buttonStyle(.borderedProminent).tint(.orange) }
        }.padding(28).frame(width: 680)
    }
}
