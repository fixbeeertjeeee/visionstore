import Foundation
import ZIPFoundation   // added automatically by the workflow's project spec

struct GuestApp: Codable, Identifiable {
    let id: String          // CFBundleIdentifier
    var name: String
    var executable: String  // CFBundleExecutable
    var folder: String      // directory name under appsRoot
}

enum ImportError: LocalizedError {
    case noApp, badPlist, encrypted
    var errorDescription: String? {
        switch self {
        case .noApp: return "No .app found in Payload/"
        case .badPlist: return "Info.plist missing or unreadable"
        case .encrypted: return "Binary is still FairPlay-encrypted (cryptid=1). Only already-decrypted IPAs you have the right to use can run."
        }
    }
}

enum IPAImporter {
    static let fm = FileManager.default

    static var appsRoot: URL {
        let d = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Applications")
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func importIPA(at ipa: URL) throws -> GuestApp {
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        try fm.unzipItem(at: ipa, to: tmp)

        let payload = tmp.appendingPathComponent("Payload")
        let contents = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
        guard let appDir = contents.first(where: { $0.pathExtension == "app" }) else { throw ImportError.noApp }

        guard let info = NSDictionary(contentsOf: appDir.appendingPathComponent("Info.plist")) as? [String: Any],
              let bid = info["CFBundleIdentifier"] as? String,
              let exe = info["CFBundleExecutable"] as? String else { throw ImportError.badPlist }

        // Refuse encrypted binaries up front instead of crashing at launch.
        if MachOTool.isEncrypted(appDir.appendingPathComponent(exe).path) { throw ImportError.encrypted }

        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? bid
        let dest = appsRoot.appendingPathComponent(bid + ".app")
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: appDir, to: dest)
        // The original signature is invalid inside the host; drop it.
        try? fm.removeItem(at: dest.appendingPathComponent("_CodeSignature"))
        return GuestApp(id: bid, name: name, executable: exe, folder: bid + ".app")
    }
}
