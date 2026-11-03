import AppKit
import Foundation

/// The folder Amir watches and what is in it, newest first. Only reads it for now: nothing is renamed or moved until the
/// naming rule is settled (2026-11-02), and then only after you agree to each one.
@MainActor
final class AmirWatcher: ObservableObject {
    struct Item: Identifiable {
        let url: URL
        let size: Int64?
        let added: Date
        let isFolder: Bool
        /// Arrived while Edit Assist was open.
        let new: Bool
        var id: URL { url }
    }
    @Published private(set) var folder: URL
    @Published private(set) var items: [Item] = []
    /// Set when the folder cannot be read, most often because macOS was not allowed to let Edit Assist into it.
    @Published private(set) var unreadable = false
    private var source: DispatchSourceFileSystemObject?
    nonisolated private let started = Date()
    /// Files still downloading: their final name appears once they are done.
    nonisolated private static let partial: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]

    init() {
        let saved = UserDefaults.standard.string(forKey: "amirFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }
        folder = saved.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        watch()
    }

    /// Asks for the folder to watch.
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = folder; panel.prompt = L("Watch this folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        UserDefaults.standard.set(url.path, forKey: "amirFolder")
        watch()
    }

    /// Reads the folder again whenever something in it changes (a file arriving, renamed or removed). Opened off the main
    /// thread: the first look into Downloads makes macOS ask for access, and the app must not freeze while it asks.
    private func watch() {
        source?.cancel(); source = nil
        let folder = folder
        Task.detached(priority: .utility) { [weak self] in
            let descriptor = open(folder.path, O_EVTONLY)
            await MainActor.run {
                guard let self, self.folder == folder else { if descriptor >= 0 { close(descriptor) }; return }
                if descriptor >= 0 {
                    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
                    source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
                    source.setCancelHandler { close(descriptor) }
                    source.resume()
                    self.source = source
                }
                self.refresh()
            }
        }
    }

    /// Opens Privacy & Security at Files and Folders, where access to the folder is turned on.
    func openFolderSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") { NSWorkspace.shared.open(url) }
    }

    func refresh() {
        let folder = folder, started = started
        Task.detached(priority: .utility) { [weak self] in
            let found = Self.read(folder, since: started)
            await MainActor.run {
                guard let self, self.folder == folder else { return }
                // Refused by macOS (Downloads, Desktop and Documents ask first): an empty list would read as an empty folder.
                self.unreadable = found == nil
                self.items = found ?? []
            }
        }
    }

    /// The folder's files, newest first, or nil when it cannot be read.
    nonisolated static func read(_ folder: URL, since started: Date) -> [Item]? {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey, .fileSizeKey, .isDirectoryKey, .isPackageKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        return urls.compactMap { url -> Item? in
            guard !partial.contains(url.pathExtension.lowercased()) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let added = values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
            let folder = values?.isDirectory == true && values?.isPackage != true
            return Item(url: url, size: folder ? nil : values?.fileSize.map(Int64.init), added: added, isFolder: folder, new: added >= started)
        }.sorted { $0.added > $1.added }
    }
}
