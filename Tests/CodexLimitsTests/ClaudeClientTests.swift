import XCTest
@testable import CodexLimits

final class ClaudeClientTests: XCTestCase {
    private static let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private static let payload = Data(#"""
    {
      "five_hour": {"utilization": 74.5, "resets_at": "2027-01-15T09:00:00.123Z"},
      "seven_day": {"utilization": 40, "resets_at": "2027-01-20T09:00:00+00:00"},
      "seven_day_sonnet": {"utilization": 95, "resets_at": "2027-01-20T09:00:00Z"},
      "seven_day_opus": null,
      "extra_usage": {"is_enabled": true, "used_credits": 500}
    }
    """#.utf8)

    func testMapsAccountWindowsAndKeepsModelWindowsSeparate() throws {
        let result = try ClaudeClient.decode(Self.payload, fetchedAt: Self.fetchedAt)

        XCTAssertEqual(result.mainLimit.limitId, "claude")
        XCTAssertEqual(result.mainLimit.name, "Claude Code")
        XCTAssertEqual(result.mainLimit.window.remainingPercent, 25.5)
        XCTAssertEqual(result.mainLimit.window.durationMinutes, 300)
        let weekly = try XCTUnwrap(result.otherLimits.first { $0.limitId == "claude" })
        XCTAssertEqual(weekly.window.durationMinutes, 10_080)
        XCTAssertEqual(weekly.window.remainingPercent, 60)
        let sonnet = try XCTUnwrap(result.otherLimits.first { $0.limitId == "claude-sonnet" })
        XCTAssertEqual(sonnet.window.remainingPercent, 5)
        XCTAssertEqual(sonnet.name, "Sonnet weekly")
        XCTAssertEqual(result.fetchedAt, Self.fetchedAt)
        XCTAssertTrue(result.tokenHistory.isEmpty)
        XCTAssertTrue(result.resetCredits.isEmpty)
        XCTAssertEqual(result.mainLimit.window.resetsAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.123, accuracy: 0.001)
    }

    func testWeeklyCanBePrimaryWithoutLosingFiveHourWindow() throws {
        let result = try ClaudeClient.decode(Data(#"""
        {"five_hour":{"utilization":10,"resets_at":"2027-01-15T09:00:00Z"},
         "seven_day":{"utilization":80,"resets_at":"2027-01-20T09:00:00Z"}}
        """#.utf8), fetchedAt: Self.fetchedAt)

        XCTAssertEqual(result.mainLimit.window.durationMinutes, 10_080)
        XCTAssertEqual(result.mainLimit.window.remainingPercent, 20)
        XCTAssertEqual(result.otherLimits.map(\.window.durationMinutes), [300])
    }

    func testNullOrMissingResetDoesNotInventAWindow() throws {
        let result = try ClaudeClient.decode(Data(#"""
        {"five_hour":{"utilization":0,"resets_at":null},
         "seven_day":{"utilization":10,"resets_at":"2027-01-20T09:00:00Z"},
         "seven_day_sonnet":{"utilization":0}}
        """#.utf8), fetchedAt: Self.fetchedAt)

        XCTAssertEqual(result.mainLimit.window.durationMinutes, 10_080)
        XCTAssertTrue(result.otherLimits.isEmpty)
    }

    func testMissingUsageAndBadDatesReportUnavailableInsteadOfZero() {
        for payload in ["{}", #"{"five_hour":{"resets_at":"invalid","utilization":10}}"#, #"{"five_hour":{"resets_at":"2027-01-15T09:00:00Z"}}"#] {
            XCTAssertThrowsError(try ClaudeClient.decode(Data(payload.utf8), fetchedAt: Self.fetchedAt)) {
                XCTAssertEqual($0 as? ClaudeClientError, .mainLimitMissing)
            }
        }
    }

    func testMalformedJSONReportsInvalidResponse() {
        XCTAssertThrowsError(try ClaudeClient.decode(Data("not json".utf8), fetchedAt: Self.fetchedAt)) {
            XCTAssertEqual($0 as? ClaudeClientError, .invalidResponse)
        }
    }

    func testClampsUtilizationToPercentageBounds() throws {
        let result = try ClaudeClient.decode(Data(#"""
        {"five_hour":{"utilization":-5,"resets_at":"2027-01-15T09:00:00Z"},
         "seven_day":{"utilization":120,"resets_at":"2027-01-20T09:00:00Z"}}
        """#.utf8), fetchedAt: Self.fetchedAt)

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 0)
        XCTAssertEqual(result.otherLimits.first?.window.remainingPercent, 100)
    }

    func testScopedLimitsHaveStableIDsAndIgnoreInactiveOrAccountScopes() throws {
        let result = try ClaudeClient.decode(Data(#"""
        {"seven_day":{"utilization":40,"resets_at":"2027-01-20T09:00:00Z"},
         "seven_day_sonnet":{"utilization":20,"resets_at":"2027-01-20T09:00:00Z"},
         "limits":[
          {"kind":"weekly_scoped","group":"weekly","percent":60,"resets_at":"2027-01-20T09:00:00Z","scope":{"model":{"id":"sonnet","display_name":"Sonnet"}}},
          {"kind":"weekly_scoped","group":"weekly","percent":30,"resets_at":"2027-01-20T09:00:00Z","scope":{"model":{"id":"fable","display_name":"Fable"}},"is_active":true},
          {"kind":"weekly_scoped","group":"weekly","percent":10,"resets_at":"2027-01-20T09:00:00Z","scope":{"model":{"id":"opus","display_name":"Opus"}},"is_active":false},
          {"kind":"weekly_scoped","group":"weekly","percent":50,"resets_at":"2027-01-20T09:00:00Z","scope":{"model":{"id":"all-models","display_name":"All models"}}}
         ]}
        """#.utf8), fetchedAt: Self.fetchedAt)

        XCTAssertEqual(result.otherLimits.map(\.limitId), ["claude-fable", "claude-sonnet"])
        XCTAssertEqual(result.otherLimits.map(\.window.remainingPercent), [70, 40])
    }

    func testRequestUsesOAuthUsageEndpointAndDoesNotSendRefreshToken() async throws {
        let credentials = ClaudeCredentials(accessToken: "fixture-access-token", expiresAt: nil)
        let result = try await ClaudeClient.fetch(credentials: credentials, now: { Self.fetchedAt }) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return (Self.payload, Self.response(status: 200))
        }
        XCTAssertEqual(result.mainLimit.window.remainingPercent, 25.5)
    }

    func testHTTPFailuresAreSanitizedAndHaveCorrectRecovery() async {
        let cases: [(Int, ClaudeClientError, Bool, Bool)] = [
            (401, .unauthorized, true, false),
            (403, .forbidden, false, false),
            (429, .rateLimited(retryAfter: nil), false, false),
            (503, .serverError(503), false, true),
            (400, .serverError(400), false, false)
        ]
        for (status, expected, requiresLogin, retries) in cases {
            do {
                _ = try await ClaudeClient.fetch(credentials: .init(accessToken: "secret", expiresAt: nil)) { _ in
                    (Data("server echoed secret".utf8), Self.response(status: status))
                }
                XCTFail("Expected HTTP failure")
            } catch let error as ClaudeClientError {
                XCTAssertEqual(error, expected)
                XCTAssertEqual(error.requiresLogin, requiresLogin)
                XCTAssertEqual(error.shouldRetryAutomatically, retries)
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            } catch {
                XCTFail("Unexpected error type")
            }
        }
    }

    func testRetryAfterAcceptsSecondsAndCaseInsensitiveHeaderNames() async throws {
        let cases = [
            ("Retry-After", "120", 120.0),
            ("retry-after", "0", 0.0),
            ("RETRY-AFTER", "00120", 120.0),
            ("rEtRy-AfTeR", " 120\t", 120.0)
        ]
        for (header, value, delay) in cases {
            let error = try await Self.rateLimitError(headers: [header: value])

            XCTAssertEqual(error, .rateLimited(retryAfter: Self.fetchedAt.addingTimeInterval(delay)))
            XCTAssertFalse(error.shouldRetryAutomatically)
            XCTAssertFalse(error.requiresLogin)
        }
    }

    func testRetryAfterAcceptsHTTPDateFormatsAndPreservesPastDates() async throws {
        let expected = Date(timeIntervalSince1970: 784_111_777)
        for value in [
            "Sun, 06 Nov 1994 08:49:37 GMT",
            "Sunday, 06-Nov-94 08:49:37 GMT",
            "Sun Nov  6 08:49:37 1994"
        ] {
            let error = try await Self.rateLimitError(headers: ["Retry-After": value])

            XCTAssertEqual(error, .rateLimited(retryAfter: expected))
        }
    }

    func testRetryAfterPreservesFutureHTTPDateDeadline() async throws {
        let error = try await Self.rateLimitError(headers: ["Retry-After": "Fri, 15 Jan 2027 09:00:00 GMT"])

        XCTAssertEqual(error, .rateLimited(retryAfter: Self.fetchedAt.addingTimeInterval(3_600)))
    }

    func testRetryAfterRejectsMalformedNegativeFractionalAndNonfiniteValues() async throws {
        for value in [
            "", " ", "-1", "+120", "1.5", "1e3", "NaN", "Infinity", "inf", "１２０",
            String(repeating: "9", count: 400), "120, 240", "not a date",
            "Sun, 31 Feb 2027 08:49:37 GMT", "Sun, 06 Nov 1994 08:49:37 GMT trailing"
        ] {
            let error = try await Self.rateLimitError(headers: ["Retry-After": value])

            XCTAssertEqual(error, .rateLimited(retryAfter: nil), "Unexpected parsed value: \(value)")
        }
    }

    func testRetryAfterSecondsStartWhenResponseArrivesAndDoNotRetry() async {
        var currentDate = Self.fetchedAt
        var requestCount = 0
        var clockReadCount = 0
        do {
            _ = try await ClaudeClient.fetch(
                credentials: .init(accessToken: "fixture", expiresAt: nil),
                now: {
                    clockReadCount += 1
                    return currentDate
                }
            ) { _ in
                requestCount += 1
                currentDate = Self.fetchedAt.addingTimeInterval(20)
                return (Data("server echoed secret".utf8), Self.response(status: 429, headers: ["Retry-After": "120"]))
            }
            XCTFail("Expected rate limit")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .rateLimited(retryAfter: Self.fetchedAt.addingTimeInterval(140)))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        } catch {
            XCTFail("Unexpected error type")
        }
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(clockReadCount, 1)
    }

    func testSuccessfulSnapshotIsTimestampedWhenResponseArrives() async throws {
        var currentDate = Self.fetchedAt
        let snapshot = try await ClaudeClient.fetch(
            credentials: .init(accessToken: "fixture", expiresAt: nil),
            now: { currentDate }
        ) { _ in
            currentDate = Self.fetchedAt.addingTimeInterval(20)
            return (Self.payload, Self.response(status: 200))
        }

        XCTAssertEqual(snapshot.fetchedAt, Self.fetchedAt.addingTimeInterval(20))
    }

    func testSuccessfulSnapshotUsesAccountEmailAfterResponseArrives() async throws {
        var responseArrived = false
        let account = ClaudeAccountReader.Account(accountID: "fixture-account", email: "fixture@example.com")
        let snapshot = try await ClaudeClient.fetch(
            credentials: .init(accessToken: "fixture", expiresAt: nil),
            account: account,
            readAccount: {
                XCTAssertTrue(responseArrived)
                return account
            }
        ) { _ in
            responseArrived = true
            return (Self.payload, Self.response(status: 200))
        }

        XCTAssertEqual(snapshot.accountEmail, "fixture@example.com")
        XCTAssertNil(try ClaudeClient.decode(Self.payload, fetchedAt: Self.fetchedAt).accountEmail)
    }

    func testCancellationIsPreserved() async {
        do {
            _ = try await ClaudeClient.fetch(credentials: .init(accessToken: "fixture", expiresAt: nil)) { _ in
                throw URLError(.cancelled)
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError")
        }
    }

    func testNetworkErrorsDoNotExposeTransportDetails() async {
        for (code, expected) in [(URLError.Code.timedOut, ClaudeClientError.timedOut), (.notConnectedToInternet, .networkUnavailable)] {
            do {
                _ = try await ClaudeClient.fetch(credentials: .init(accessToken: "fixture", expiresAt: nil)) { _ in
                    throw URLError(code, userInfo: [NSLocalizedDescriptionKey: "secret"])
                }
                XCTFail("Expected network failure")
            } catch let error as ClaudeClientError {
                XCTAssertEqual(error, expected)
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            } catch {
                XCTFail("Unexpected error type")
            }
        }
    }

    private static func response(status: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    private static func rateLimitError(headers: [String: String]) async throws -> ClaudeClientError {
        do {
            _ = try await ClaudeClient.fetch(
                credentials: .init(accessToken: "fixture", expiresAt: nil),
                now: { Self.fetchedAt }
            ) { _ in
                (Data("server echoed secret".utf8), Self.response(status: 429, headers: headers))
            }
            return try XCTUnwrap(nil as ClaudeClientError?, "Expected rate limit")
        } catch let error as ClaudeClientError {
            return error
        }
    }
}
