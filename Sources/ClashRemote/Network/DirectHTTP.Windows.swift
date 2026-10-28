#if os(Windows)
import Foundation
import CWindowsPlatform

/// WinHTTP bypasses system proxies and retains certificate validation and redirect responses.
enum DirectHTTP {
    static func request(url: URL, method: String, headers: [String: String], body: Data?, timeout: TimeInterval) async throws -> HTTPResponse {
        let data = body ?? Data()
        let fields = headers.map { "\($0.key): \($0.value)\r\n" }.joined()
        return try await Task.detached {
            var result = data.withUnsafeBytes { buffer in
                cr_http(url.absoluteString, method, fields, buffer.bindMemory(to: UInt8.self).baseAddress,
                        data.count, Int32(min(max(timeout * 1000, 1000), Double(Int32.max))))
            }
            defer { cr_http_free(&result) }
            guard result.error == 0 else { throw HTTPError.message("Windows 网络请求失败（WinHTTP \(result.error)）") }
            var parsed: [String: String] = [:]
            if let raw = result.headers {
                for line in String(cString: raw).components(separatedBy: "\r\n") {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = String(line[..<colon]).lowercased()
                    let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    parsed[key] = parsed[key].map { $0 + "\n" + value } ?? value
                }
            }
            let responseData = result.data.map { Data(bytes: $0, count: result.count) } ?? Data()
            return HTTPResponse(status: Int(result.status), data: responseData, headers: parsed)
        }.value
    }
}
#endif
