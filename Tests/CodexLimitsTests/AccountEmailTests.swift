import XCTest
@testable import CodexLimits

final class AccountEmailTests: XCTestCase {
    func testSavedSnapshotRetainsItsFetchedAccountEmail() throws {
        let snapshot = try codexSnapshot(account: #"{"type":"chatgpt","email":"first@example.test"}"#)

        let restored = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored.accountName, "first@example.test")
    }

    func testLegacySnapshotWithoutAccountEmailStillDecodes() throws {
        let snapshot = try codexSnapshot(account: #"{"type":"chatgpt","email":"fixture@example.test"}"#)
        let encoded = try JSONEncoder().encode(snapshot)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payload.removeValue(forKey: "accountEmail")

        let restored = try JSONDecoder().decode(
            UsageSnapshot.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        XCTAssertNil(restored.accountName)
        XCTAssertEqual(restored.mainLimit, snapshot.mainLimit)
    }

    func testCodexReadsOnlyTheChatGPTAccountEmail() throws {
        XCTAssertEqual(
            try codexSnapshot(account: #"{"type":"chatgpt","email":"  fixture@example.test  "}"#).accountName,
            "fixture@example.test"
        )
        for account in [
            "null",
            #"{"type":"chatgpt","email":null}"#,
            #"{"type":"chatgpt","email":"  "}"#,
            #"{"type":"apiKey","email":"unrelated@example.test"}"#,
            #"{"type":"futureAccount","email":"unrelated@example.test"}"#
        ] {
            XCTAssertNil(try codexSnapshot(account: account).accountName)
        }
    }

    func testOptionalCodexAccountFailureDoesNotDiscardUsage() async throws {
        for accountResponse in [
            #"{"id":4,"error":{"code":-32601,"message":"Method not found"}}"#,
            #"{"id":4,"error":null}"#,
            #"{"id":4,"result":{"account":{"type":"chatgpt","email":42}}}"#
        ] {
            let snapshot = try await readCodexSnapshot(responses: [
                Self.initializedResponse,
                Self.rateLimitsResponse,
                Self.usageResponse,
                accountResponse
            ])

            XCTAssertNil(snapshot.accountName)
            XCTAssertEqual(snapshot.mainLimit.window.remainingPercent, 80)
        }
    }

    func testCodexAccountAndUsageResponsesCanArriveInEitherOrder() async throws {
        let accountResponse = #"{"id":4,"result":{"account":{"type":"chatgpt","email":"fixture@example.test"}}}"#
        for responses in [
            [Self.initializedResponse, accountResponse, Self.rateLimitsResponse, Self.usageResponse],
            [Self.initializedResponse, Self.rateLimitsResponse, Self.usageResponse, accountResponse]
        ] {
            let snapshot = try await readCodexSnapshot(responses: responses)

            XCTAssertEqual(snapshot.accountName, "fixture@example.test")
            XCTAssertEqual(snapshot.mainLimit.window.remainingPercent, 80)
        }
    }

    func testClaudeReadsDefaultLocalAccountConfig() {
        var paths: [String] = []
        let account = ClaudeAccountReader.read(
            environment: [:],
            homeDirectory: Self.home,
            workingDirectory: Self.workingDirectory,
            fileExists: { _ in false },
            readFile: { url in
                paths.append(url.path)
                return Data(Self.claudeAccount.utf8)
            }
        )

        XCTAssertEqual(paths, ["/fixture/home/.claude.json"])
        XCTAssertEqual(account?.accountID, "fixture-account")
        XCTAssertEqual(account?.email, "fixture@example.test")
    }

    func testClaudeCustomProfileNeverFallsBackToDefaultHome() {
        var paths: [String] = []
        let account = ClaudeAccountReader.read(
            environment: ["CLAUDE_CONFIG_DIR": "profiles/work,personal"],
            homeDirectory: Self.home,
            workingDirectory: Self.workingDirectory,
            fileExists: { _ in false },
            readFile: { url in
                paths.append(url.path)
                throw CocoaError(.fileReadNoSuchFile)
            }
        )

        XCTAssertNil(account)
        XCTAssertEqual(paths, ["/fixture/work/profiles/work,personal/.claude.json"])
    }

    func testClaudeExistingLegacyConfigTakesPrecedence() {
        var paths: [String] = []
        let account = ClaudeAccountReader.read(
            environment: ["CLAUDE_CONFIG_DIR": "/fixture/profile"],
            homeDirectory: Self.home,
            workingDirectory: Self.workingDirectory,
            fileExists: { $0 == "/fixture/profile/.config.json" },
            readFile: { url in
                paths.append(url.path)
                return Data(Self.claudeAccount.utf8)
            }
        )

        XCTAssertEqual(account?.email, "fixture@example.test")
        XCTAssertEqual(paths, ["/fixture/profile/.config.json"])
    }

    func testClaudeDoesNotCombineMetadataWithAnotherSecureStorageProfile() {
        var readCount = 0
        for secureDirectory in ["/fixture/other", ""] {
            let account = ClaudeAccountReader.read(
                environment: [
                    "CLAUDE_CONFIG_DIR": "/fixture/profile",
                    "CLAUDE_SECURESTORAGE_CONFIG_DIR": secureDirectory
                ],
                homeDirectory: Self.home,
                workingDirectory: Self.workingDirectory,
                fileExists: { _ in false },
                readFile: { _ in
                    readCount += 1
                    return Data(Self.claudeAccount.utf8)
                }
            )
            XCTAssertNil(account)
        }
        XCTAssertEqual(readCount, 0)
    }

    func testClaudeMatchingSecureStorageOverrideCanUseProfileMetadata() {
        let account = ClaudeAccountReader.read(
            environment: [
                "CLAUDE_CONFIG_DIR": "/fixture/profile",
                "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/fixture/profile"
            ],
            homeDirectory: Self.home,
            workingDirectory: Self.workingDirectory,
            fileExists: { _ in false },
            readFile: { _ in Data(Self.claudeAccount.utf8) }
        )
        XCTAssertEqual(account?.email, "fixture@example.test")
    }

    func testClaudeUnknownOrMalformedAccountDoesNotGuessAnEmail() {
        for payload in [
            "not json",
            "{}",
            #"{"emailAddress":"unrelated@example.test"}"#,
            #"{"oauthAccount":{"emailAddress":"fixture@example.test"}}"#,
            #"{"oauthAccount":{"accountUuid":"fixture-account","emailAddress":null}}"#,
            #"{"oauthAccount":{"accountUuid":"fixture-account","emailAddress":"  "}}"#,
            #"{"oauthAccount":{"accountUuid":"fixture-account","emailAddress":"first\nsecond@example.test"}}"#
        ] {
            let account = ClaudeAccountReader.read(
                environment: [:],
                homeDirectory: Self.home,
                workingDirectory: Self.workingDirectory,
                fileExists: { _ in false },
                readFile: { _ in Data(payload.utf8) }
            )
            XCTAssertNil(account)
        }
    }

    func testClaudeAttachesAccountThatStaysStableDuringCommand() async throws {
        let snapshot = try await fetchClaudeSnapshot(before: Self.firstAccount, after: Self.firstAccount)
        XCTAssertEqual(snapshot.accountName, Self.firstAccount.email)
    }

    func testClaudeAccountSwitchDuringCommandOmitsEmail() async throws {
        let snapshot = try await fetchClaudeSnapshot(before: Self.firstAccount, after: Self.secondAccount)
        XCTAssertNil(snapshot.accountName)
    }

    func testClaudeMissingAccountCannotAcquireEmailLater() async throws {
        let cases: [(ClaudeAccountReader.Account?, ClaudeAccountReader.Account?)] = [(nil, Self.firstAccount), (Self.firstAccount, nil)]
        for accounts in cases {
            let snapshot = try await fetchClaudeSnapshot(before: accounts.0, after: accounts.1)
            XCTAssertNil(snapshot.accountName)
        }
    }

    private func fetchClaudeSnapshot(
        before: ClaudeAccountReader.Account?, after: ClaudeAccountReader.Account?
    ) async throws -> UsageSnapshot {
        var account = before
        return try await ClaudeClient.fetch(readAccount: { account }) {
            account = after
            return try ClaudeUsageFixture.output()
        }
    }

    private func codexSnapshot(account: String) throws -> UsageSnapshot {
        try CodexClient.decode(
            rateLimitsResponse: Data(Self.rateLimitsResponse.utf8),
            usageResponse: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_000),
            accountResponse: Data("{\"result\":{\"account\":\(account)}}".utf8)
        )
    }

    private func readCodexSnapshot(responses: [String]) async throws -> UsageSnapshot {
        let output = Pipe()
        let input = Pipe()
        defer {
            try? input.fileHandleForReading.close()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        try output.fileHandleForWriting.write(contentsOf: Data((responses.joined(separator: "\n") + "\n").utf8))
        try output.fileHandleForWriting.close()
        return try await CodexClient.readSnapshot(
            from: output.fileHandleForReading,
            writingTo: input.fileHandleForWriting,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private static let home = URL(fileURLWithPath: "/fixture/home", isDirectory: true)
    private static let workingDirectory = URL(fileURLWithPath: "/fixture/work", isDirectory: true)
    private static let claudeAccount = #"{"oauthAccount":{"accountUuid":"fixture-account","emailAddress":"fixture@example.test"}}"#
    private static let firstAccount = ClaudeAccountReader.Account(accountID: "fixture-first", email: "first@example.test")
    private static let secondAccount = ClaudeAccountReader.Account(accountID: "fixture-second", email: "second@example.test")
    private static let initializedResponse = #"{"id":1,"result":{}}"#
    private static let usageResponse = #"{"id":3,"result":{}}"#
    private static let rateLimitsResponse = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}}}}"#
}
