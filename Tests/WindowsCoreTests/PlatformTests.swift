import XCTest
import Foundation
@testable import ClashRemote

final class PlatformTests: XCTestCase {
    func testWindowsCryptoMatchesKnownVectors() {
        let input = Array("hello".utf8)
        var md5 = [UInt8](repeating: 0, count: 16)
        var sha = [UInt8](repeating: 0, count: 32)
        input.withUnsafeBytes { p in
            _ = CC_MD5(p.baseAddress, UInt32(input.count), &md5)
            _ = CC_SHA256(p.baseAddress, UInt32(input.count), &sha)
        }
        XCTAssertEqual(hex(md5), "5d41402abc4b2a76b9719d911017c592")
        XCTAssertEqual(hex(sha), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        let key = [UInt8](repeating: 0x0b, count: 16)
        let message = Array("Hi There".utf8)
        var hmac = [UInt8](repeating: 0, count: 16)
        key.withUnsafeBytes { k in message.withUnsafeBytes { m in
            CCHmac(kCCHmacAlgMD5, k.baseAddress, key.count, m.baseAddress, message.count, &hmac)
        } }
        XCTAssertEqual(hex(hmac), "9294727a3638bb1c13f48ef8158bfc9d")
    }

    func testTrafficCountersRejectBooleansAndFractions() throws {
        let json = try JSONSerialization.jsonObject(with: Data("{\"yes\":true,\"one\":1,\"zero\":0}".utf8)) as! [String: Any]
        XCTAssertNil(TrafficCounter.parse(json["yes"]))
        XCTAssertNil(TrafficCounter.parse(NSNumber(value: true)))
        XCTAssertEqual(TrafficCounter.parse(json["one"]), 1)
        XCTAssertEqual(TrafficCounter.parse(json["zero"]), 0)
        XCTAssertNil(TrafficCounter.parse(1.5))
        XCTAssertNil(TrafficCounter.parse(-1))
        XCTAssertEqual(TrafficCounter.parse("9223372036854775807"), Int64.max)
    }

    func testHTTPPreservesRedirectCookiesAndUTF8Body() async throws {
        let base = try fixtureURL()
        let client = HTTPClient(timeout: 2)
        let response = try await client.request(url: base.appending(path: "redirect"))
        XCTAssertEqual(response.status, 302)
        XCTAssertTrue(response.headers["set-cookie", default: ""].contains("sysauth_http=test-token"))
        XCTAssertTrue(response.headers["set-cookie", default: ""].contains("other=value"))
        let text = "测试 Windows 请求"
        let echo = try await client.request(url: base.appending(path: "echo"), method: "POST", headers: ["X-Test": "bridge"], body: Data(text.utf8))
        let json = try echo.jsonDict()
        XCTAssertEqual(json["body"] as? String, text)
        XCTAssertEqual(json["method"] as? String, "POST")
        XCTAssertEqual(json["header"] as? String, "bridge")
        XCTAssertEqual(json["cookie"] as? String, "")
    }

    @MainActor
    func testOriginalOpenClashLoginOverWindowsTransport() async throws {
        let url = try fixtureURL()
        let client = OpenClashClient(device: RouterDevice(name: "test", host: "127.0.0.1", port: url.port!, password: "fixture-only"))
        try await client.login()
        XCTAssertEqual(client.ubusSid, "fixture-session")
        XCTAssertEqual(client.luciCookie, "test-token")
    }

    @MainActor
    func testServiceStartStopRestartAndAllModes() async throws {
        let url = try fixtureURL()
        let http = HTTPClient()
        _ = try await http.request(url: url.appending(path: "fixture/reset"))
        let service = OpenClashService(device: RouterDevice(name: "mock", host: "127.0.0.1", port: url.port!, password: "fixture-only"))
        let initial = try await service.connect()
        XCTAssertFalse(initial.status.running)
        try await service.setRunning(true)
        let started = try await service.refresh(full: false)
        XCTAssertTrue(started.status.running)
        try await service.setRunning(false)
        let stopped = try await service.refresh(full: false)
        XCTAssertFalse(stopped.status.running)
        try await service.restart()
        let restarted = try await service.refresh(full: false)
        XCTAssertTrue(restarted.status.running)
        for mode in RuleMode.allCases {
            try await service.setRuleMode(mode)
            let snapshot = try await service.refresh(full: false)
            XCTAssertEqual(snapshot.status.ruleMode, mode)
        }
        let response = try await http.request(url: url.appending(path: "fixture/requests"))
        let records = try response.jsonDict()["requests"] as! [[String: Any]]
        let actions = records.filter { ($0["path"] as? String)?.hasSuffix("/action") == true }
        XCTAssertEqual(actions.compactMap { ($0["query"] as? [String: [String]])?["action"]?.first }, ["start", "stop", "restart"])
        XCTAssertTrue(actions.allSatisfy { ($0["cookie"] as? String)?.contains("sysauth_http=test-token") == true })
        let patches = records.filter { $0["method"] as? String == "PATCH" }
        XCTAssertEqual(patches.compactMap { ($0["body"] as? [String: String])?["mode"] }, RuleMode.allCases.map(\.rawValue))
        XCTAssertTrue(patches.allSatisfy { $0["auth"] as? String == "Bearer fixture-secret" })
    }

    func testInvalidURLReturnsAnError() async {
        do {
            _ = try await HTTPClient().request(url: URL(string: "file:///test")!)
            XCTFail("Invalid protocol must fail")
        } catch { }
    }

    private func fixtureURL() throws -> URL {
        guard let value = ProcessInfo.processInfo.environment["CR_TEST_URL"], let url = URL(string: value) else {
            throw XCTSkip("Run scripts/test-windows-core.py to enable loopback HTTP tests")
        }
        return url
    }
    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}
