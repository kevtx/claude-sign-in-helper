import Foundation
import AppKit
import Security
import Darwin

struct Inspection {
    enum State { case ready, closeDesktop, existingSession }
    let state: State
    let version: String
}

struct BackupManifest: Codable {
    var formatVersion = 2
    var helperVersion = Format.version
    var action: String
    var state = "prepared"
    var createdUTC: String
    var profile: String
    var backupSHA256: String
    var logInode: UInt64?
    var logOffset: UInt64
    var importFingerprint: String?
    var cookieNames: [String]?
    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version", helperVersion = "helper_version", action, state
        case createdUTC = "created_utc", profile, backupSHA256 = "backup_sha256"
        case logInode = "log_inode", logOffset = "log_offset", importFingerprint = "import_fingerprint", cookieNames = "cookie_names"
    }
}

struct SavedBackup: Identifiable {
    let id: String
    let manifest: BackupManifest
    var canRestore: Bool { manifest.action == "import" && manifest.state != "restored" && manifest.importFingerprint != nil }
    var date: Date? { backupDateFormatter().date(from: manifest.createdUTC) }
}

func backupDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return formatter
}

func privateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let info = try fileInfo(url)
    try require(info.st_mode & S_IFMT == S_IFDIR, "backup_owner", "Unexpected backup folder", "The private backup folder cannot be a symbolic link.")
    try require(chmod(url.path, 0o700) == 0, "backup_permissions", "The backup could not be protected", "No login data was changed.")
}

final class OperationLock {
    private let descriptor: Int32
    init(_ paths: LocalPaths) throws {
        try privateDirectory(paths.backups.deletingLastPathComponent())
        try privateDirectory(paths.backups)
        descriptor = open(paths.backups.appendingPathComponent(".operation.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw HelperFailure(code: "lock", title: "The private backup folder is unavailable", detail: "No cookie changes were made.") }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            throw HelperFailure(code: "busy", title: "Another import is running", detail: "Wait for the other helper operation to finish, then try again.")
        }
    }
    deinit { close(descriptor) }
}

final class SessionEngine {
    let paths: LocalPaths
    init(paths: LocalPaths) { self.paths = paths }

    func officialVersion() throws -> String {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let expression = "identifier \"\(Format.appID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(Format.teamID)\""
        let created = SecStaticCodeCreateWithPath(paths.app as CFURL, SecCSFlags(), &code)
        let parsed = SecRequirementCreateWithString(expression as CFString, SecCSFlags(), &requirement)
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard created == errSecSuccess, parsed == errSecSuccess, let signedCode = code,
              SecStaticCodeCheckValidity(signedCode, flags, requirement) == errSecSuccess else {
            throw HelperFailure(code: "signature", title: "The official app could not be verified", detail: "Install an unmodified copy of Claude Desktop from Anthropic, then check again. No login data was changed.")
        }
        let info = try Data(contentsOf: paths.app.appendingPathComponent("Contents/Info.plist"))
        guard let dictionary = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any],
              dictionary["CFBundleIdentifier"] as? String == Format.appID,
              let version = dictionary["CFBundleShortVersionString"] as? String,
              version.range(of: "^[0-9A-Za-z.+_-]{1,60}$", options: .regularExpression) != nil else {
            throw HelperFailure(code: "app_identity", title: "The app identity is unfamiliar", detail: "This preview only works with the official Claude Desktop app.")
        }
        return version
    }
    static func isDesktopRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Format.appID || ($0.bundleURL?.path.contains("/Claude.app/") ?? false)
        }
    }
    static func requireClosed() throws {
        try require(!isDesktopRunning(), "app_running", "Quit Claude Desktop first", "Use Command-Q in Claude Desktop, then try again. Keep Safari signed in.")
    }
    func inspect() throws -> Inspection {
        let version = try officialVersion()
        let database = try CookieDatabase(paths.database)
        if try database.hasLogin() { return Inspection(state: .existingSession, version: version) }
        _ = try SafariReader.parse(safeRead(paths.safari))
        return Inspection(state: Self.isDesktopRunning() ? .closeDesktop : .ready, version: version)
    }
    func repair(progress: (String) -> Void) throws -> SavedBackup {
        progress("Checking the installed app…")
        _ = try officialVersion()
        try Self.requireClosed()
        try CookieDatabase(paths.database).requireNoLogin()
        let cookies = try SafariReader.parse(safeRead(paths.safari))
        progress("Waiting for macOS Keychain…")
        let key = try CookieCrypto.keyFromKeychain()
        try Self.requireClosed()
        progress("Saving a backup and importing…")
        return try importCookies(cookies, key: key)
    }
    func saveManifest(_ manifest: BackupManifest, folder: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = folder.appendingPathComponent("manifest.json")
        try encoder.encode(manifest).write(to: url, options: .atomic)
        try require(chmod(url.path, 0o600) == 0, "backup_permissions", "Backup permissions could not be set", "Keep your backup and check the disk’s availability.")
    }
    func makeBackup(_ database: CookieDatabase, action: String) throws -> SavedBackup {
        let stamp = backupDateFormatter().string(from: Date())
        let id = stamp + "-" + UUID().uuidString.prefix(8).lowercased()
        let folder = paths.backups.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent("Cookies")
        try database.backup(to: file)
        let log = try? fileInfo(paths.log)
        let manifest = BackupManifest(action: action, createdUTC: stamp, profile: paths.profile.path,
                                      backupSHA256: try safeRead(file).sha256.hex, logInode: log.map { UInt64($0.st_ino) },
                                      logOffset: UInt64(max(0, log?.st_size ?? 0)))
        try saveManifest(manifest, folder: folder)
        return SavedBackup(id: id, manifest: manifest)
    }
    // Internal operation also used with isolated, synthetic databases in the test runner.
    func importCookies(_ cookies: [String: SessionCookie], key: Data) throws -> SavedBackup {
        try require(cookies["sessionKey"] != nil && Set(cookies.keys).isSubset(of: Set(Format.names)), "selection", "Unexpected session selection", "No cookies were imported.")
        for (name, cookie) in cookies {
            try require(cookie.name == name && Format.domains.contains(cookie.domain) && cookie.expires > Date().timeIntervalSince1970 && (name != "sessionKey" || cookie.httpOnly),
                        "selection", "The session changed or expired", "Check this Mac again before importing.")
        }
        let lock = try OperationLock(paths); defer { withExtendedLifetime(lock) {} }
        let database = try CookieDatabase(paths.database, writable: true)
        try database.requireNoLogin(); try database.verifyKey(key)
        let rows = try cookies.values.map { try encryptedRow($0, key: key) }
        let saved = try makeBackup(database, action: "import")
        let folder = paths.backups.appendingPathComponent(saved.id)
        var manifest = saved.manifest
        try database.query("BEGIN EXCLUSIVE")
        var committed = false
        defer { if !committed { _ = try? database.query("ROLLBACK") } }
        try database.requireNoLogin()
        for row in rows {
            try database.query("DELETE FROM cookies WHERE host_key IN ('claude.ai','.claude.ai') AND name=? AND path='/' AND top_frame_site_key=''", [row[3]])
            try database.insert(row)
        }
        for cookie in cookies.values {
            let stored = try database.query("SELECT encrypted_value,value FROM cookies WHERE host_key=? AND name=? AND path='/' AND top_frame_site_key=''", [.text(cookie.domain), .text(cookie.name)])
            try require(stored.count == 1 && stored[0][1].string.isEmpty, "write_verification", "The import did not verify", "Its transaction will be rolled back.")
            let decoded = try CookieCrypto.open(stored[0][0].data, domain: cookie.domain, key: key)
            try require(decoded.same(as: cookie.value), "write_verification", "The import did not verify", "Its transaction will be rolled back.")
        }
        try database.integrity()
        manifest.importFingerprint = try database.fingerprint(); manifest.cookieNames = cookies.keys.sorted()
        try saveManifest(manifest, folder: folder)
        try database.query("COMMIT"); committed = true
        manifest.state = "committed"
        try? saveManifest(manifest, folder: folder) // Prepared metadata already contains the undo information.
        return SavedBackup(id: saved.id, manifest: manifest)
    }

    func loadBackup(_ id: String) throws -> SavedBackup {
        try require(id.range(of: "^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$", options: .regularExpression) != nil,
                    "backup_id", "That backup is not recognized", "Choose a backup from the list in this app.")
        let folder = paths.backups.appendingPathComponent(id)
        let info = try fileInfo(folder)
        try require(info.st_mode & S_IFMT == S_IFDIR, "backup_owner", "Unexpected backup folder", "The folder must belong to your Mac account and cannot be a symbolic link.")
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: safeRead(folder.appendingPathComponent("manifest.json"), limit: 65536))
        try require([1, 2].contains(manifest.formatVersion) && manifest.profile == paths.profile.path,
                    "backup_profile", "This backup belongs to a different profile", "It cannot be restored into this Mac account.")
        let checksum = try safeRead(folder.appendingPathComponent("Cookies")).sha256.hex
        try require(checksum == manifest.backupSHA256, "backup_changed", "The backup has changed", "Its checksum no longer matches. It will not be restored.")
        return SavedBackup(id: id, manifest: manifest)
    }
    func backups() throws -> [SavedBackup] {
        guard FileManager.default.fileExists(atPath: paths.backups.path) else { return [] }
        let info = try fileInfo(paths.backups)
        try require(info.st_mode & S_IFMT == S_IFDIR, "backup_owner", "Unexpected backup folder", "Your backups cannot be loaded from a symbolic link.")
        let urls = try FileManager.default.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)
        return try urls.map(\.lastPathComponent).filter { $0.range(of: "^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$", options: .regularExpression) != nil }
            .sorted(by: >).map { try loadBackup($0) }.filter { $0.manifest.action == "import" }
    }
    func restore(_ id: String, validateApp: Bool = true) throws {
        if validateApp { _ = try officialVersion(); try Self.requireClosed() }
        let lock = try OperationLock(paths); defer { withExtendedLifetime(lock) {} }
        let saved = try loadBackup(id)
        try require(saved.canRestore, "backup_state", "This backup cannot be restored", "Choose an import that has not already been undone.")
        let folder = paths.backups.appendingPathComponent(id)
        let original = try CookieDatabase(folder.appendingPathComponent("Cookies"))
        let oldRows = try original.selectedRows()
        let database = try CookieDatabase(paths.database, writable: true)
        if try database.fingerprint() != saved.manifest.importFingerprint, try !database.hasLogin() {
            throw HelperFailure(code: "session_removed", title: "Desktop no longer has the imported sign-in", detail: "Claude Desktop removed the imported session, so there’s nothing to undo. Nothing was changed.")
        }
        try require(try database.fingerprint() == saved.manifest.importFingerprint, "newer_session", "Desktop has a newer sign-in", "Restoring this backup would replace newer session data, so the helper stopped. Your current sign-in is unchanged.")
        let checkpoint = try makeBackup(database, action: "restore-checkpoint")
        try database.query("BEGIN EXCLUSIVE")
        var committed = false
        defer { if !committed { _ = try? database.query("ROLLBACK") } }
        try require(try database.fingerprint() == saved.manifest.importFingerprint, "newer_session", "The session changed during restore", "Nothing will be replaced.")
        try database.query("DELETE FROM cookies WHERE " + Format.selection)
        for row in oldRows { try database.insert(row) }
        try database.integrity()
        try database.query("COMMIT"); committed = true
        var manifest = saved.manifest; manifest.state = "restored"
        try? saveManifest(manifest, folder: folder)
        var checkpointManifest = checkpoint.manifest; checkpointManifest.state = "committed"
        try? saveManifest(checkpointManifest, folder: paths.backups.appendingPathComponent(checkpoint.id))
    }
    func verify() throws -> Bool {
        guard let saved = try backups().first(where: \.canRestore) else {
            throw HelperFailure(code: "no_import", title: "There is no import to verify yet", detail: "Verification checks imports made by this helper. You can check your current account directly in Claude Desktop.")
        }
        let database = try CookieDatabase(paths.database)
        guard try database.hasLogin() else { return false }
        guard let info = try? fileInfo(paths.log), info.st_size >= 0,
              UInt64(info.st_size) >= saved.manifest.logOffset,
              saved.manifest.logInode == nil || saved.manifest.logInode == UInt64(info.st_ino) else { return false }
        let data = try safeRead(paths.log, offset: saved.manifest.logOffset)
        return String(decoding: data, as: UTF8.self).contains("claude.ai account active and logged in")
    }
}
