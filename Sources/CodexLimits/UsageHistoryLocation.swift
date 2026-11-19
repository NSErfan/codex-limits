//
//  UsageHistoryLocation.swift
//  CodexLimits
//
//  Created by Erfan on 19/11/26.
//

import Foundation

struct UsageHistoryLocation: Equatable {
    let directory: URL
    let syncSubdirectory: String?
    let subscription: UsageSubscriptionKey?
}
