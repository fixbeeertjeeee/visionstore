import SwiftUI
import UniformTypeIdentifiers

@main struct IPAPlayerApp: App { var body: some Scene { WindowGroup { LibraryView() } } }

struct LibraryView: View {
    @State private var apps: [GuestApp] = Self.load()
    @State private var picking = false
    @State private var busy = false
    @State private var message: String?

    // .item/.data make every file selectable, so the Open button can never stay greyed out.
    static var pickerTypes: [UTType] {
        var t: [UTType] = [.item, .data, .zip]
        if let ipa = UTType("com.apple.itunes.ipa") { t.insert(ipa, at: 0) }
        if let ext = UTType(filenameExtension: "ipa") { t.insert(ext, at: 0) }
        return t
    }

    var body: some View {
        NavigationView {
            Group {
                if apps.isEmpty {
                    VStack(spacing: 12) {
                        Text("No apps yet").font(.headline)
                        Text("Tap + to pick an IPA, or copy IPAs into Files > On My iPhone > IPA Player and reopen this app.")
                            .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }.padding()
                } else {
                    List(apps) { app in
                        Button(app.name) { launch(app) }
                            .swipeActions { Button("Delete", role: .destructive) { remove(app) } }
                    }
                }
            }
            .navigationTitle("IPA Player")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { scanDocuments() } label: { Image(systemName: "arrow.clockwise") }
                    Button { picking = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: Self.pickerTypes, allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): for u in urls { importFile(u) }
                case .failure(let e): message = e.localizedDescription
                }
            }
            .overlay {
                if busy {
                    ProgressView("Importing…").padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("IPA Player", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
        .navigationViewStyle(.stack)
        .onOpenURL { importFile($0) }
        .onAppear { scanDocuments() }
    }

    func importFile(_ url: URL, deleteAfter: Bool = false) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let app = try IPAImporter.importIPA(at: url)
                if deleteAfter { try? FileManager.default.removeItem(at: url) }
                DispatchQueue.main.async {
                    apps.removeAll { $0.id == app.id }
                    apps.append(app)
                    Self.save(apps)
                    busy = false
                }
            } catch {
                DispatchQueue.main.async {
                    message = "\(url.lastPathComponent): \(error.localizedDescription)"
                    busy = false
                }
            }
        }
    }

    // Picks up any .ipa dropped into the app's Documents folder via the Files app.
    func scanDocuments() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension.lowercased() == "ipa" { importFile(f, deleteAfter: true) }
    }

    func launch(_ a: GuestApp) {
        let root = IPAImporter.appsRoot
        _ = LaunchGuest(root.appendingPathComponent(a.folder).path, a.id, a.executable,
                        root.deletingLastPathComponent().appendingPathComponent("GuestData/\(a.id)").path)
    }

    func remove(_ a: GuestApp) {
        apps.removeAll { $0.id == a.id }
        try? FileManager.default.removeItem(at: IPAImporter.appsRoot.appendingPathComponent(a.folder))
        Self.save(apps)
    }

    static let key = "guestApps"
    static func load() -> [GuestApp] {
        (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([GuestApp].self, from: $0) } ?? []
    }
    static func save(_ a: [GuestApp]) { UserDefaults.standard.set(try? JSONEncoder().encode(a), forKey: key) }
}
