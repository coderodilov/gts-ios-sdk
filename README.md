# gts-ios-sdk

Official iOS Swift Package SDK for Global Travel APIs, including authentication and flight booking flows.

## Installation

Add the package in Xcode with:

```text
https://github.com/coderodilov/gts-ios-sdk.git
```

Or add it to `Package.swift`:

```swift
.package(url: "https://github.com/coderodilov/gts-ios-sdk.git", from: "1.0.1")
```

## Basic Usage

```swift
import GtsSdk

let session = try await GtsSdk.authenticate(
    email: sdkEmail,
    password: sdkPassword
)

let sdk = session.sdk
let currency = session.currency ?? "USD"
```

## Development

```bash
swift test
```
