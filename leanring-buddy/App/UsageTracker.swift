//
//  UsageTracker.swift
//  leanring-buddy
//
//  Tracks local token and message usage against configurable credit limits.
//  Persists counts to UserDefaults so they survive app restarts.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class UsageTracker: ObservableObject {

    @Published private(set) var totalMessagesUsed: Int
    @Published private(set) var totalTokensUsed: Int

    let messageLimit: Int
    let tokenLimit: Int

    private static let messagesUsedKey = "usageTracker_messagesUsed"
    private static let tokensUsedKey = "usageTracker_tokensUsed"
    private static let lastResetDateKey = "usageTracker_lastResetDate"

    var messagesRemaining: Int {
        max(0, messageLimit - totalMessagesUsed)
    }

    var tokensRemaining: Int {
        max(0, tokenLimit - totalTokensUsed)
    }

    var messageUsagePercent: Double {
        guard messageLimit > 0 else { return 0 }
        return min(1.0, Double(totalMessagesUsed) / Double(messageLimit))
    }

    var tokenUsagePercent: Double {
        guard tokenLimit > 0 else { return 0 }
        return min(1.0, Double(totalTokensUsed) / Double(tokenLimit))
    }

    var hasReachedMessageLimit: Bool {
        totalMessagesUsed >= messageLimit
    }

    var hasReachedTokenLimit: Bool {
        totalTokensUsed >= tokenLimit
    }

    var hasReachedAnyLimit: Bool {
        hasReachedMessageLimit || hasReachedTokenLimit
    }

    init(messageLimit: Int = 50, tokenLimit: Int = 100_000) {
        self.messageLimit = messageLimit
        self.tokenLimit = tokenLimit
        self.totalMessagesUsed = UserDefaults.standard.integer(forKey: Self.messagesUsedKey)
        self.totalTokensUsed = UserDefaults.standard.integer(forKey: Self.tokensUsedKey)

        resetIfNewDay()
    }

    func recordMessage(estimatedTokenCount: Int) {
        totalMessagesUsed += 1
        totalTokensUsed += estimatedTokenCount

        UserDefaults.standard.set(totalMessagesUsed, forKey: Self.messagesUsedKey)
        UserDefaults.standard.set(totalTokensUsed, forKey: Self.tokensUsedKey)
    }

    func resetUsage() {
        totalMessagesUsed = 0
        totalTokensUsed = 0
        UserDefaults.standard.set(0, forKey: Self.messagesUsedKey)
        UserDefaults.standard.set(0, forKey: Self.tokensUsedKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastResetDateKey)
    }

    static func estimateTokenCount(forText text: String) -> Int {
        // Rough heuristic: ~4 characters per token for English text.
        // OpenAI's tokenizer averages ~3.5-4 chars/token for typical content.
        max(1, text.count / 4)
    }

    // MARK: - Daily Reset

    private func resetIfNewDay() {
        let lastResetTimestamp = UserDefaults.standard.double(forKey: Self.lastResetDateKey)
        guard lastResetTimestamp > 0 else {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastResetDateKey)
            return
        }

        let lastResetDate = Date(timeIntervalSince1970: lastResetTimestamp)
        if !Calendar.current.isDateInToday(lastResetDate) {
            resetUsage()
        }
    }

    // MARK: - Formatted Display Strings

    var formattedTokensUsed: String {
        formatNumber(totalTokensUsed)
    }

    var formattedTokenLimit: String {
        formatNumber(tokenLimit)
    }

    var formattedTokensRemaining: String {
        formatNumber(tokensRemaining)
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            let thousands = Double(number) / 1000.0
            if thousands == Double(Int(thousands)) {
                return "\(Int(thousands))k"
            }
            return String(format: "%.1fk", thousands)
        }
        return "\(number)"
    }
}
