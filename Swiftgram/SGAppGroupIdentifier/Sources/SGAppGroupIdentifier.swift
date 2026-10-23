import Foundation

public let FALLBACK_BASE_BUNDLE_ID: String = "app.swiftgram.ios"

public func sgBaseBundleIdentifier() -> String {
    let baseBundleId: String
    if let bundleId: String = Bundle.main.bundleIdentifier {
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            if let lastDotRange: Range<String.Index> = bundleId.range(of: ".", options: [.backwards]) {
                baseBundleId = String(bundleId[..<lastDotRange.lowerBound])
            } else {
                baseBundleId = FALLBACK_BASE_BUNDLE_ID
            }
        } else {
            baseBundleId = bundleId
        }
    } else {
        baseBundleId = FALLBACK_BASE_BUNDLE_ID
    }
    return baseBundleId
}

public func sgAppGroupIdentifier() -> String {
    // Nova: a re-signed build can only use the app group from its provisioning profile,
    // so Info.plist may override it with NovaAppGroup.
    let result: String
    if let override = Bundle.main.object(forInfoDictionaryKey: "NovaAppGroup") as? String, !override.isEmpty {
        result = override
    } else {
        result = "group.\(sgBaseBundleIdentifier())"
    }
    
    #if DEBUG
    print("APP_GROUP_IDENTIFIER: \(result)")
    #endif
    
    return result
}
