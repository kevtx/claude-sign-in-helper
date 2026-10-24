import Foundation
import Darwin

// This runner only uses fabricated credentials and its own temporary directory.
private let publicKey = Data("0123456789abcdef".utf8)
private let fakeSession = Data("PUBLIC-SYNTHETIC-SESSION-FOR-TESTS".utf8)
private let testNow: Double = 1800000000

private func expect(_ condition: @autoclosure () throws -> Bool) throws {
    if try !condition() { throw HelperFailure(code: "test_assertion", title: "Test failed", detail: "Synthetic assertion failed.") }
}
private func expectFailure(_ operation: () throws -> Void) throws {
    do { try operation() }
    catch is HelperFailure { return }
    throw HelperFailure(code: "expected_rejection", title: "Test failed", detail: "A synthetic invalid input was not rejected.")
}
private func put(_ value: UInt64, into data: inout Data, at offset: Int, count: Int = 4, big: Bool = false) {
    for n in 0..<count { data[offset + n] = UInt8(truncatingIfNeeded: value >> ((big ? count - 1 - n : n) * 8)) }
}
private func record(name: String = "sessionKey", domain: String = ".claude.ai", value: Data = fakeSession,
                    flags: UInt64 = 5, expires: Double = testNow + 3600, path: String = "/") -> Data {
    var data = Data(repeating: 0, count: 56)
    for (n, field) in [Data(domain.utf8), Data(name.utf8), Data(path.utf8), value].enumerated() {
        put(UInt64(data.count), into: &data, at: 16 + n * 4); data.append(field); data.append(0)
    }
    put(UInt64(data.count), into: &data, at: 0); put(flags, into: &data, at: 8)
    put((expires - Format.appleEpoch).bitPattern, into: &data, at: 40, count: 8)
    put((testNow - 60 - Format.appleEpoch).bitPattern, into: &data, at: 48, count: 8)
    return data
}
private func binary(_ records: [Data]) -> Data {
    var page = Data(repeating: 0, count: 12 + 4 * records.count)
    page[2] = 1; put(UInt64(records.count), into: &page, at: 4)
    for (n, record) in records.enumerated() { put(UInt64(page.count), into: &page, at: 8 + n * 4); page.append(record) }
    var file = Data("cook".utf8) + Data(repeating: 0, count: 8)
    put(1, into: &file, at: 4, big: true); put(UInt64(page.count), into: &file, at: 8, big: true)
    file.append(page); return file
}
private func cookie(_ name: String = "sessionKey", value: Data = fakeSession, domain: String = ".claude.ai", expires: Double = Date().timeIntervalSince1970 + 3600) -> SessionCookie {
    SessionCookie(domain: domain, name: name, value: value, expires: expires,
                  created: Date().timeIntervalSince1970 - 60, httpOnly: name == "sessionKey")
}

private final class Fixture {
    let root: URL
    let paths: LocalPaths
    let engine: SessionEngine
    let cookies = ["sessionKey": cookie(), "lastActiveOrg": cookie("lastActiveOrg", value: Data("PUBLIC-ORG".utf8)),
                   "anthropic-device-id": cookie("anthropic-device-id", value: Data("PUBLIC-SAFARI-DEVICE".utf8))]
    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("claude-native-test-" + UUID().uuidString)
        paths = LocalPaths(home: root, app: root.appendingPathComponent("Applications/Claude.app"))
        engine = SessionEngine(paths: paths)
        try FileManager.default.createDirectory(at: paths.profile, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let db = try CookieDatabase(paths.database, writable: true, create: true, validate: false)
        let strings = Set(["host_key", "top_frame_site_key", "name", "value", "path"])
        let columns = Format.columns.map { $0 + ($0 == "encrypted_value" ? " BLOB" : strings.contains($0) ? " TEXT" : " INTEGER") + " NOT NULL" }
        try db.query("CREATE TABLE meta(key TEXT NOT NULL UNIQUE PRIMARY KEY,value TEXT)")
        try db.query("INSERT INTO meta VALUES ('version','24'),('last_compatible_version','24')")
        try db.query("CREATE TABLE cookies(" + columns.joined(separator: ",") + ")")
        try db.query("CREATE UNIQUE INDEX cookies_unique_index ON cookies(" + Format.uniqueColumns.joined(separator: ",") + ")")
        try db.insert(encryptedRow(cookie("anthropic-device-id", value: Data("PUBLIC-DEVICE-ID".utf8), domain: "claude.ai"), key: publicKey))
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func rows() throws -> [[SQLValue]] { try CookieDatabase(paths.database).query("SELECT * FROM cookies ORDER BY host_key,name") }
    func runImport() throws -> SavedBackup { try engine.importCookies(cookies, key: publicKey) }
}

func runSelfTests() -> Int32 {
    var passed = 0; var failed = 0
    func test(_ name: String, _ work: () throws -> Void) {
        do { try work(); passed += 1; print("PASS " + name) }
        catch { failed += 1; print("FAIL " + name + " [" + readableFailure(error).code + "]") }
    }
    test("Safari cookie domain and flags") {
        for domain in Format.domains {
            let result = try SafariReader.parse(binary([record(domain: domain)]), now: testNow)
            try expect(result["sessionKey"]?.domain == domain && result["sessionKey"]?.httpOnly == true)
            try expect(result["sessionKey"]?.value == fakeSession)
        }
    }
    test("Only exact Claude domains and allowed names") {
        let result = try SafariReader.parse(binary([record(), record(domain: "claude.ai.attacker.example"), record(domain: "other.example"), record(name: "unrelated")]), now: testNow)
        try expect(Set(result.keys) == ["sessionKey"])
    }
    test("All three permitted cookies") {
        let result = try SafariReader.parse(binary([record(), record(name: "lastActiveOrg", flags: 1), record(name: "anthropic-device-id", flags: 1)]), now: testNow)
        try expect(Set(result.keys) == Set(Format.names))
    }
    test("Expired session rejected") { try expectFailure { _ = try SafariReader.parse(binary([record(expires: testNow - 1)]), now: testNow) } }
    test("Expired optional cookie ignored") {
        let result = try SafariReader.parse(binary([record(), record(name: "lastActiveOrg", expires: testNow - 1)]), now: testNow)
        try expect(result.count == 1)
    }
    test("Missing protection flags rejected") {
        for flags: UInt64 in [0, 1, 4] { try expectFailure { _ = try SafariReader.parse(binary([record(flags: flags)]), now: testNow) } }
    }
    test("Ambiguous session rejected") { try expectFailure { _ = try SafariReader.parse(binary([record(), record(domain: "claude.ai")]), now: testNow) } }
    test("Newer session format rejected") { try expectFailure { _ = try SafariReader.parse(binary([record(), record(name: "sessionKeyV3")]), now: testNow) } }
    test("Non-root cookie scope rejected") { try expectFailure { _ = try SafariReader.parse(binary([record(path: "/private")]), now: testNow) } }
    test("Truncated input and invalid offsets rejected") {
        let full = binary([record()])
        for count in [0, 1, 7, 8, 11, 12, full.count - 1] { try expectFailure { _ = try SafariReader.parse(Data(full.prefix(count)), now: testNow) } }
        var entry = record(); put(100000, into: &entry, at: 28)
        try expectFailure { _ = try SafariReader.parse(binary([entry]), now: testNow) }
    }
    test("Nonfinite and enormous expiry rejected") {
        for expiry in [Double.nan, Double.infinity, 1e20] { try expectFailure { _ = try SafariReader.parse(binary([record(expires: expiry)]), now: testNow) } }
    }
    test("AES matches independent OpenSSL golden vector") {
        let plain = Data("public test data for AES-CBC".utf8)
        let encrypted = try CookieCrypto.transform(plain, key: publicKey)
        try expect(encrypted.hex == "0281264a306fa90ee0b637c261feb0df3fd3d9de9b974832617b881976444e0d")
        try expect(try CookieCrypto.transform(encrypted, key: publicKey, decrypt: true) == plain)
    }
    test("PBKDF2 matches independent Python golden vector") {
        try expect(try CookieCrypto.derive(Data("public-test-password".utf8)).hex == "14cbbaa7b64dce4ef1620fad5cda3812")
    }
    test("Encrypted cookie is bound to its hostname") {
        let sample = cookie(); let encrypted = try CookieCrypto.seal(sample, key: publicKey)
        try expectFailure { _ = try CookieCrypto.open(encrypted, domain: "other.example", key: publicKey) }
    }
    test("Python v1 fingerprint compatibility") {
        let fixture = try Fixture()
        try expect(try CookieDatabase(fixture.paths.database).fingerprint() == "e4528c2e790bb2195d74b91b6cfe5c7fbc3ddd9fc559973f525e5ced614aed3e")
    }
    test("Import encryption and private backup") {
        let fixture = try Fixture(); let before = try fixture.rows(); let saved = try fixture.runImport()
        let backup = fixture.paths.backups.appendingPathComponent(saved.id)
        try expect(try fileInfo(backup).st_mode & 0o777 == 0o700)
        try expect(try fileInfo(backup.appendingPathComponent("Cookies")).st_mode & 0o777 == 0o600)
        try expect(try CookieDatabase(backup.appendingPathComponent("Cookies")).query("SELECT * FROM cookies ORDER BY host_key,name") == before)
        let rows = try CookieDatabase(fixture.paths.database).query("SELECT value,encrypted_value FROM cookies WHERE name='sessionKey'")
        try expect(rows[0][0].string.isEmpty)
        try expect(try CookieCrypto.open(rows[0][1].data, domain: ".claude.ai", key: publicKey) == fakeSession)
        try expect(try safeRead(fixture.paths.database).range(of: fakeSession) == nil)
    }
    test("Existing Desktop login preserved") {
        let fixture = try Fixture(); _ = try fixture.runImport(); let before = try fixture.rows()
        try expectFailure { _ = try fixture.runImport() }; try expect(try fixture.rows() == before)
    }
    test("Wrong Keychain key cannot modify cookies") {
        let fixture = try Fixture(); let before = try fixture.rows()
        try expectFailure { _ = try fixture.engine.importCookies(fixture.cookies, key: Data("fedcba9876543210".utf8)) }
        try expect(try fixture.rows() == before)
    }
    test("Write failure rolls back the whole import") {
        let fixture = try Fixture(); let before = try fixture.rows()
        try CookieDatabase(fixture.paths.database, writable: true).query("CREATE TRIGGER synthetic_failure BEFORE INSERT ON cookies WHEN NEW.name='sessionKey' BEGIN SELECT RAISE(ABORT,'synthetic'); END")
        try expectFailure { _ = try fixture.runImport() }; try expect(try fixture.rows() == before)
    }
    test("Restore preserves unrelated new cookies") {
        let fixture = try Fixture(); let before = try fixture.rows(); let saved = try fixture.runImport()
        let extra = try encryptedRow(cookie("unrelated", value: Data("PUBLIC-OTHER".utf8), domain: "example.test"), key: publicKey)
        try CookieDatabase(fixture.paths.database, writable: true).insert(extra)
        try fixture.engine.restore(saved.id, validateApp: false)
        try expect(try fixture.rows() == before + [extra])
    }
    test("Restore refuses a newer login") {
        let fixture = try Fixture(); let saved = try fixture.runImport()
        let db = try CookieDatabase(fixture.paths.database, writable: true)
        try db.query("UPDATE cookies SET encrypted_value=? WHERE name='sessionKey'", [.blob(Data("NEW-SYNTHETIC-SESSION".utf8))])
        let before = try fixture.rows()
        try expectFailure { try fixture.engine.restore(saved.id, validateApp: false) }; try expect(try fixture.rows() == before)
    }
    test("Restore explains a removed session") {
        let fixture = try Fixture(); let saved = try fixture.runImport()
        try CookieDatabase(fixture.paths.database, writable: true).query("DELETE FROM cookies WHERE name='sessionKey'")
        let before = try fixture.rows()
        do { try fixture.engine.restore(saved.id, validateApp: false); try expect(false) }
        catch let failure as HelperFailure where failure.code != "test_assertion" { try expect(failure.code == "session_removed") }
        try expect(try fixture.rows() == before)
    }
    test("Altered backup cannot be restored") {
        let fixture = try Fixture(); let saved = try fixture.runImport()
        let file = fixture.paths.backups.appendingPathComponent(saved.id + "/Cookies")
        let stream = try FileHandle(forWritingTo: file); try stream.seekToEnd(); try stream.write(contentsOf: Data("ALTERED".utf8)); try stream.close()
        try expectFailure { try fixture.engine.restore(saved.id, validateApp: false) }
    }
    test("Future database schema rejected") {
        let fixture = try Fixture()
        try CookieDatabase(fixture.paths.database, writable: true).query("UPDATE meta SET value='25' WHERE key='version'")
        try expectFailure { _ = try fixture.runImport() }
    }
    test("Expired during approval is rejected") {
        let fixture = try Fixture(); let before = try fixture.rows()
        try expectFailure { _ = try fixture.engine.importCookies(["sessionKey": cookie(expires: Date().timeIntervalSince1970 - 1)], key: publicKey) }
        try expect(try fixture.rows() == before)
    }
    test("Verification ignores historical sign-in logs") {
        let fixture = try Fixture(); let marker = Data("claude.ai account active and logged in\n".utf8)
        try FileManager.default.createDirectory(at: fixture.paths.log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try marker.write(to: fixture.paths.log); _ = try fixture.runImport()
        try expect(try !fixture.engine.verify())
        let stream = try FileHandle(forWritingTo: fixture.paths.log); try stream.seekToEnd(); try stream.write(contentsOf: marker); try stream.close()
        try expect(try fixture.engine.verify())
    }
    test("Symlink database rejected") {
        let fixture = try Fixture(); let original = fixture.paths.profile.appendingPathComponent("original")
        try FileManager.default.moveItem(at: fixture.paths.database, to: original)
        try FileManager.default.createSymbolicLink(at: fixture.paths.database, withDestinationURL: original)
        try expectFailure { _ = try fixture.runImport() }
    }
    test("Database creation never overwrites an existing file") {
        let fixture = try Fixture(); let before = try safeRead(fixture.paths.database)
        try expectFailure { _ = try CookieDatabase(fixture.paths.database, writable: true, create: true, validate: false) }
        try expect(try safeRead(fixture.paths.database) == before)
    }
    test("Database rejects a symbolic link in its parent path") {
        let fixture = try Fixture(); let link = fixture.root.appendingPathComponent("linked-profile")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.paths.profile)
        try expectFailure { _ = try CookieDatabase(link.appendingPathComponent("Cookies")) }
    }
    test("Version 1 backup manifest can be restored") {
        let fixture = try Fixture(); let before = try fixture.rows(); let saved = try fixture.runImport()
        var manifest = saved.manifest; manifest.formatVersion = 1; manifest.helperVersion = "0.1.0"
        try fixture.engine.saveManifest(manifest, folder: fixture.paths.backups.appendingPathComponent(saved.id))
        try fixture.engine.restore(saved.id, validateApp: false)
        try expect(try fixture.rows() == before)
    }
    test("Backup IDs cannot escape the backup folder") {
        let fixture = try Fixture(); try expectFailure { _ = try fixture.engine.loadBackup("../../another-account") }
    }
    test("Unexpected errors are redacted") {
        let error = NSError(domain: "SYNTHETIC", code: 1, userInfo: [NSLocalizedDescriptionKey: String(decoding: fakeSession, as: UTF8.self)])
        try expect(!readableFailure(error).detail.contains(String(decoding: fakeSession, as: UTF8.self)))
    }
    print("\(passed) passed; \(failed) failed. Synthetic fixtures only; no live account access.")
    return failed == 0 ? 0 : 1
}
