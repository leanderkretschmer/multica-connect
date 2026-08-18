import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one seam between ``MulticaAPIClient`` and the network, so tests can run
/// the whole client without a server.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession`-backed transport used by the app.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        #if canImport(Darwin)
        // Apple platforms can hold a request until the radio is usable; the
        // Linux port exposes this as read-only.
        configuration.waitsForConnectivity = true
        #endif
        self.session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MulticaError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw MulticaError.transport("The response was not HTTP.")
        }
        return (data, http)
    }
}
