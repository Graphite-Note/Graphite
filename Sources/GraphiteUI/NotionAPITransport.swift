/**
 * File: NotionAPITransport.swift
 * ------------------------------
 * Layer: UI
 * Description: How an import through Notion's API reaches Notion: its requests sent with URLSession, the integration's
 *              token added to the requests to Notion's API alone, and the clock the Importer keeps Notion's rate by.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import Foundation
import NotionImport

/// Sends the Importer's requests with an ephemeral `URLSession`, which keeps no cookie or cache on disk. The token is
/// added only to a request the Importer marks for Notion's API whose address is Notion's API, and taken off again when
/// an answer sends the request to another server, so a file's address never sees it.
struct NotionURLSessionTransport: NotionTransport {
    /// The server of Notion's API, the only one the token is sent to.
    static let apiHost = "api.notion.com"

    private let token: String
    private let session: URLSession

    init(token: String) {
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration)
    }

    func send(_ request: NotionRequest) async throws -> NotionResponse {
        guard let urlRequest = Self.urlRequest(for: request, token: token) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(for: urlRequest, delegate: NotionRedirectGuard())
        guard let answer = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let headers = answer.allHeaderFields.compactMap { name, value -> NotionHeader? in
            guard let name = name as? String else { return nil }
            return NotionHeader(name: name, value: "\(value)")
        }
        return NotionResponse(status: answer.statusCode, headers: headers, body: Array(data))
    }

    /// The `URLRequest` of `request`: https only, the Importer's headers but any authorization of its own, and the
    /// token for Notion's API. Nil for an address that is not https.
    static func urlRequest(for request: NotionRequest, token: String) -> URLRequest? {
        guard let url = URL(string: request.url), url.scheme?.lowercased() == "https" else { return nil }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for header in request.headers where header.name.lowercased() != "authorization" {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if request.isNotionAPI, url.host?.lowercased() == apiHost {
            urlRequest.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = request.body.map { body in Data(body) }
        return urlRequest
    }
}

/// Takes the token off a request that an answer redirects to a server other than Notion's API.
final class NotionRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        Self.redirected(request)
    }

    static func redirected(_ request: URLRequest) -> URLRequest {
        guard request.url?.host?.lowercased() != NotionURLSessionTransport.apiHost else { return request }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        return stripped
    }
}

/// The Importer's clock: the monotonic `clock` it is given, counted from the moment the import starts, and waits that
/// end early when the import is cancelled.
struct NotionContinuousClock: NotionClock {
    private let clock: ContinuousClock
    private let start: ContinuousClock.Instant

    init(clock: ContinuousClock = ContinuousClock()) {
        self.clock = clock
        start = clock.now
    }

    func nowMilliseconds() -> Int64 {
        let elapsed = start.duration(to: clock.now)
        return elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000
    }

    func sleep(milliseconds: Int64) async throws {
        try await clock.sleep(for: .milliseconds(milliseconds))
    }
}
