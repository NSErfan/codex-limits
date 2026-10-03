import XCTest
@testable import CodexLimits

final class AccountEmailTests: XCTestCase {
    func testSavedSnapshotRetainsItsFetchedAccountEmail() throws {
        let snapshot = try codexSnapshot(account: #"{"type":"chatgpt","email":"first@example.test"}"#)

        let restored = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored.accountEmail, "first@example.test")
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

        XCTAssertNil(restored.accountEmail)
        XCTAssertEqual(restored.mainLimit, snapshot.mainLimit)
    }

    func testCodexReadsOnlyTheChatGPTAccountEmail() throws {
        XCTAssertEqual(
            try codexSnapshot(account: #"{"type":"chatgpt","email":"  fixture@example.test  "}"#).accountEmail,
            "fixture@example.test"
        )
        for account in [
            "null",
            #"{"type":"chatgpt","email":null}"#,
            #"{"type":"chatgpt","email":"  "}"#,
            #"{"type":"apiKey","email":"unrelated@example.test"}"#,
            #"{"type":"futureAccount","email":"unrelated@example.test"}"#
        ] {
            XCTAssertNil(try codexSnapshot(account: account).accountEmail)
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

            XCTAssertNil(snapshot.accountEmail)
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

            XCTAssertEqual(snapshot.accountEmail, "fixture@example.test")
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

    func testClaudeAttachesAccountThatStaysStableThroughCredentialReadAndResponse() async throws {
        let snapshot = try await fetchClaudeSnapshot(
            beforeCredentials: Self.firstAccount,
            afterCredentials: Self.firstAccount,
            afterResponse: Self.firstAccount
        )
        XCTAssertEqual(snapshot.accountEmail, Self.firstAccount.email)
    }

    func testClaudeAccountSwitchDuringCredentialReadOmitsEmail() async throws {
        let snapshot = try await fetchClaudeSnapshot(
            beforeCredentials: Self.firstAccount,
            afterCredentials: Self.secondAccount,
            afterResponse: Self.secondAccount
        )
        XCTAssertNil(snapshot.accountEmail)
    }

    func testClaudeAccountSwitchDuringRequestOmitsEmail() async throws {
        let snapshot = try await fetchClaudeSnapshot(
            beforeCredentials: Self.firstAccount,
            afterCredentials: Self.firstAccount,
            afterResponse: Self.secondAccount
        )
        XCTAssertNil(snapshot.accountEmail)
    }

    func testClaudeMissingCaptureCannotAcquireEmailLater() async throws {
        let cases: [(ClaudeAccountReader.Account?, ClaudeAccountReader.Account?)] = [
            (nil, Self.firstAccount), (Self.firstAccount, nil)
        ]
        for accounts in cases {
            let snapshot = try await fetchClaudeSnapshot(
                beforeCredentials: accounts.0,
                afterCredentials: accounts.1,
                afterResponse: Self.firstAccount
            )
            XCTAssertNil(snapshot.accountEmail)
        }
    }

    private func fetchClaudeSnapshot(
        beforeCredentials: ClaudeAccountReader.Account?,
        afterCredentials: ClaudeAccountReader.Account?,
        afterResponse: ClaudeAccountReader.Account?
    ) async throws -> UsageSnapshot {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AccountEmailTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = AccountFixture(account: beforeCredentials)
        let result = try await ClaudeUsageCoordinator(directory: directory).fetch(
            allowCredentialPrompt: false,
            readAccount: { fixture.readAccount() },
            readCredentials: { _ in fixture.readCredentials(accountAfterRead: afterCredentials) },
            request: { credentials, account in
                try await ClaudeClient.fetch(credentials: credentials, account: account, readAccount: {
                    fixture.readAccount()
                }) { _ in
                    fixture.setAccount(afterResponse)
                    return (
                        Data(#"{"five_hour":{"utilization":20,"resets_at":"2030-01-01T00:00:00Z"}}"#.utf8),
                        HTTPURLResponse(url: URL(string: "https://example.test/usage")!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!
                    )
                }
            }
        )
        XCTAssertEqual(fixture.credentialsReadCount, 1)
        guard case let .fetched(snapshot, _) = result else {
            return try XCTUnwrap(nil, "Expected a fresh usage snapshot")
        }
        return snapshot
    }

    private final class AccountFixture: @unchecked Sendable {
        private let lock = NSLock()
        private var account: ClaudeAccountReader.Account?
        private var storedCredentialsReadCount = 0

        init(account: ClaudeAccountReader.Account?) { self.account = account }

        var credentialsReadCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedCredentialsReadCount
        }

        func readAccount() -> ClaudeAccountReader.Account? {
            lock.lock()
            defer { lock.unlock() }
            return account
        }

        func readCredentials(accountAfterRead: ClaudeAccountReader.Account?) -> ClaudeCredentials {
            lock.lock()
            defer { lock.unlock() }
            storedCredentialsReadCount += 1
            account = accountAfterRead
            return ClaudeCredentials(accessToken: "fixture-access-token", expiresAt: nil)
        }

        func setAccount(_ account: ClaudeAccountReader.Account?) {
            lock.lock()
            defer { lock.unlock() }
            self.account = account
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
