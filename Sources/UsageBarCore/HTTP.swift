import Foundation

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Sends the request and maps HTTP failures to `UsageError`.
    /// `isTokenRequest` treats 400 as a rejected grant (expired or revoked refresh token).
    static func data(for request: URLRequest, isTokenRequest: Bool = false) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UsageError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw UsageError.unknownResponse }
        switch http.statusCode {
        case 200 ..< 300: return data
        case 401, 403: throw UsageError.unauthorized
        case 400 where isTokenRequest: throw UsageError.unauthorized
        case 429: throw UsageError.rateLimited
        default: throw UsageError.http(http.statusCode)
        }
    }

    static func postJSON(_ url: URL, _ body: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func postForm(_ url: URL, _ body: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(body.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").utf8)
        return request
    }

    static func json(_ data: Data) throws -> [String: Any] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageError.unknownResponse
        }
        return object
    }
}
