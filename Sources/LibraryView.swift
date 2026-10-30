import SwiftUI
import UniformTypeIdentifiers

@main struct IPAPlayerApp: App { var body: some Scene { WindowGroup { LibraryView() } } }

struct LibraryView: View {
    @State private var apps: [GuestApp] = Self.load()
    @State private var picking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List(apps) { app in
                Button(app.name) { launch(app) }
                    .swipeActions { Button("Delete", role: .destructive) { remove(app) } }
            }
            .navigationTitle("IPA Player")
            .toolbar { Button { picking = true } label: { Image(systemName: "plus") } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "ipa")!], allowsMultipleSelection: true) { r in
                for url in (try? r.get()) ?? [] {
                    _ = url.startAccessingSecurityScopedResource(); defer { url.stopAccessingSecurityScopedResource() }
                    do { apps.append(try IPAImporter.importIPA(at: url)); Self.save(apps) }
                    catch { self.error = error.localizedDescription }
                }
            }
            .alert("Import failed", isPresented: .constant(error != nil)) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }

    func launch(_ a: GuestApp) {
        let root = IPAImporter.appsRoot
        _ = LaunchGuest(root.appendingPathComponent(a.folder).path, a.id, a.executable,
                        root.deletingLastPathComponent().appendingPathComponent("GuestData/\(a.id)").path)
    }
    func remove(_ a: GuestApp) { apps.removeAll { $0.id == a.id }; try? FileManager.default.removeItem(at: IPAImporter.appsRoot.appendingPathComponent(a.folder)); Self.save(apps) }

    static let key = "guestApps"
    static func load() -> [GuestApp] { (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([GuestApp].self, from: $0) } ?? [] }
    static func save(_ a: [GuestApp]) { UserDefaults.standard.set(try? JSONEncoder().encode(a), forKey: key) }
}
