import Foundation

/// Which Zuno API a client's no-key tracking lookups go to.
public enum ZunoEnvironment: Sendable, Equatable {
    case production
    case sandbox
    /// A self-hosted or local gateway, e.g. `http://192.168.1.20:8000/api`.
    case custom(URL)

    public var apiURL: URL {
        switch self {
        case .production: return URL(string: "https://api.zunodelivery.com/api")!
        case .sandbox: return URL(string: "https://api-gateway-staging-6b3d.up.railway.app/api")!
        case .custom(let url): return url
        }
    }
}

/// Called before every request to the integrator backend. Use it to attach
/// the app user's session (for example `Authorization: Bearer …`) that the
/// backend checks before forwarding the call to Zuno with its API key.
public typealias ZunoRequestAuthorizer = @Sendable (inout URLRequest) async throws -> Void

public struct ZunoConfiguration: Sendable {
    /// The integrator backend that proxies Zuno. It must mirror Zuno's paths
    /// below `/api`: `POST {backendURL}/public/quotes` is forwarded to
    /// `POST https://api.zunodelivery.com/api/public/quotes` with `X-Api-Key`.
    public var backendURL: URL
    /// Where `trackDelivery(trackingNumber:)` goes. That lookup needs no API
    /// key, so it calls Zuno directly instead of the backend.
    public var environment: ZunoEnvironment
    public var authorizer: ZunoRequestAuthorizer?
    public var urlSession: URLSession
    public var timeout: TimeInterval

    public init(
        backendURL: URL,
        environment: ZunoEnvironment = .production,
        authorizer: ZunoRequestAuthorizer? = nil,
        urlSession: URLSession = .shared,
        timeout: TimeInterval = 30
    ) {
        self.backendURL = backendURL
        self.environment = environment
        self.authorizer = authorizer
        self.urlSession = urlSession
        self.timeout = timeout
    }
}
