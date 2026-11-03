# Zuno iOS SDK

Native Swift client for Zuno's developer delivery API. Requires iOS 15+ and a Swift 6 toolchain.

## Install

Add `https://github.com/fening/zuno-ios-sdk` in Xcode's Package Dependencies, choosing version 0.1.0 or newer. For a Swift package:

```swift
.package(url: "https://github.com/fening/zuno-ios-sdk.git", from: "0.1.0")
```

Add the `ZunoSDK` product to your target, then `import ZunoSDK`.

## Configure

Tenant API keys must remain on your backend. Your backend authenticates app users, enforces order ownership and proxies Zuno's paths below `/api`, attaching its tenant API key. The SDK authorizer attaches your app user's own session:

```swift
import Foundation
import ZunoSDK

let zuno = ZunoClient(
    backendURL: URL(string: "https://api.yourcompany.com/zuno")!,
    authorizer: { request in
        request.setValue("Bearer YOUR_APP_SESSION", forHTTPHeaderField: "Authorization")
    }
)
let quote = try await zuno.createQuote(QuoteRequest(
    pickup: Coordinate(latitude: 5.556, longitude: -0.182),
    dropoff: Coordinate(latitude: 5.6052, longitude: -0.1668)
))
```

`trackDelivery(trackingNumber:)` is public and calls Zuno directly without the authorizer. All other methods use your backend. Production is the default; use `.sandbox` for staging.

## API

- Quotes and funded order creation with explicit idempotency keys.
- Order/status reads, lifecycle polling, cancellation and driver contact/avatar.
- Rider chat: send, page messages and mark read. Persist `conversationId` with its cursor; omit both when discovering a reassigned rider's conversation. Retain the conversation ID to read completed-delivery history.
- GhanaPostGPS address resolution/encoding and recipient-safe tracking.

Store one `ZunoIdempotencyKey.make()` value per logical delivery and reuse it only for identical retries. `ZunoError` exposes HTTP errors and retryability; order retries require the same idempotency key. Money uses `Decimal`; server string values accept future additions.

See the [integration guide](https://developers.zunodelivery.com/docs/mobile-sdks) and [API reference](https://developers.zunodelivery.com/docs/api-reference). Polling supplements backend webhooks; it is not a persistent background connection.

## Develop

Run `swift test`. This repository is the SDK-only distribution of Zuno's maintained source. Releases use semantic version tags and are immutable.

## License

MIT. See [LICENSE](LICENSE).
