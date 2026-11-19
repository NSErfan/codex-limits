//
//  UsageSubscriptionKey.swift
//  CodexLimits
//
//  Created by Erfan on 19/11/26.
//

import CryptoKit
import Foundation

struct UsageSubscriptionKey: RawRepresentable, Codable, Equatable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        guard rawValue.utf8.count == 64,
              rawValue.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 102).contains($0) }) else { return nil }
        self.rawValue = rawValue
    }

    init(workspaceID: String, accountName: String) {
        let identity = "\(workspaceID)\u{0}\(accountName.lowercased())"
        rawValue = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
