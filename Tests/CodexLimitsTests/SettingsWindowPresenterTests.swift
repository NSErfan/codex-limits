import AppKit
import XCTest
@testable import CodexLimits

@MainActor
final class SettingsWindowPresenterTests: XCTestCase {
    func testFirstOpeningWaitsForTheSettingsWindow() async {
        var events: [String] = []
        let presenter = SettingsWindowPresenter(activateApplication: { events.append("activate") })
        let window = makeWindow()
        window.onPresentation = { events.append("present") }

        presenter.open(using: { events.append("open") })
        await drainPresentationQueue()
        XCTAssertEqual(events, ["open"])

        presenter.attach(window)
        await drainPresentationQueue()
        XCTAssertEqual(events, ["open", "present", "activate"])

        presenter.attach(window)
        await drainPresentationQueue()
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testAttachingWithoutAnOpenRequestDoesNotTakeFocus() async {
        var activationCount = 0
        let presenter = SettingsWindowPresenter(activateApplication: { activationCount += 1 })
        let window = makeWindow()

        presenter.attach(window)
        await drainPresentationQueue()

        XCTAssertEqual(window.presentationCount, 0)
        XCTAssertEqual(activationCount, 0)
    }

    func testOpeningConfiguresTheKnownWindowBeforeTheSwiftUIAction() async {
        let presenter = SettingsWindowPresenter(activateApplication: {})
        let window = makeWindow()
        presenter.attach(window)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        var actionCount = 0

        presenter.open(using: {
            actionCount += 1
            XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
            XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
            XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        })
        await drainPresentationQueue()

        XCTAssertEqual(actionCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testOpeningTargetsOnlyTheRegisteredSettingsWindow() async {
        let presenter = SettingsWindowPresenter(activateApplication: {})
        let settingsWindow = makeWindow()
        let activityWindow = makeWindow()
        activityWindow.identifier = NSUserInterfaceItemIdentifier("model-activity")
        activityWindow.collectionBehavior = [.canJoinAllSpaces]
        presenter.attach(settingsWindow)

        presenter.open(using: {})
        await drainPresentationQueue()

        XCTAssertEqual(settingsWindow.presentationCount, 1)
        XCTAssertEqual(activityWindow.presentationCount, 0)
        XCTAssertEqual(activityWindow.collectionBehavior, [.canJoinAllSpaces])
    }

    func testClosedSettingsWindowCanBePresentedAgain() async {
        var activationCount = 0
        let presenter = SettingsWindowPresenter(activateApplication: { activationCount += 1 })
        let window = makeWindow()
        presenter.attach(window)
        presenter.open(using: {})
        await drainPresentationQueue()

        window.close()
        presenter.open(using: {})
        await drainPresentationQueue()

        XCTAssertEqual(window.presentationCount, 2)
        XCTAssertEqual(activationCount, 2)
    }

    func testAReplacementWindowReceivesTheQueuedPresentation() async {
        var activationCount = 0
        let presenter = SettingsWindowPresenter(activateApplication: { activationCount += 1 })
        let previousWindow = makeWindow()
        let replacementWindow = makeWindow()
        presenter.attach(previousWindow)
        presenter.open(using: {})

        presenter.attach(replacementWindow)
        presenter.detach(previousWindow)
        await drainPresentationQueue()

        XCTAssertEqual(previousWindow.presentationCount, 0)
        XCTAssertEqual(replacementWindow.presentationCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    func testDetachingPreservesTheRequestUntilAReplacementArrives() async {
        var activationCount = 0
        let presenter = SettingsWindowPresenter(activateApplication: { activationCount += 1 })
        let previousWindow = makeWindow()
        presenter.attach(previousWindow)
        presenter.open(using: {})
        presenter.detach(previousWindow)
        await drainPresentationQueue()

        XCTAssertEqual(previousWindow.presentationCount, 0)
        XCTAssertEqual(activationCount, 0)

        let replacementWindow = makeWindow()
        presenter.attach(replacementWindow)
        await drainPresentationQueue()

        XCTAssertEqual(replacementWindow.presentationCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    func testMinimizedSettingsWindowIsRestoredBeforePresentation() async {
        var events: [String] = []
        let presenter = SettingsWindowPresenter(activateApplication: { events.append("activate") })
        let window = makeWindow()
        window.simulatesMiniaturization = true
        window.onRestoration = { events.append("restore") }
        window.onPresentation = {
            XCTAssertFalse(window.isMiniaturized)
            events.append("present")
        }
        presenter.attach(window)

        presenter.open(using: {})
        await drainPresentationQueue()

        XCTAssertEqual(events, ["restore", "present", "activate"])
    }

    func testPresenterDoesNotRetainAnAttachedWindow() async {
        var activationCount = 0
        let presenter = SettingsWindowPresenter(activateApplication: { activationCount += 1 })
        weak var releasedWindow: WindowSpy?
        autoreleasepool {
            let window = makeWindow()
            releasedWindow = window
            presenter.attach(window)
        }
        XCTAssertNil(releasedWindow)

        presenter.open(using: {})
        await drainPresentationQueue()
        XCTAssertEqual(activationCount, 0)

        let replacementWindow = makeWindow()
        presenter.attach(replacementWindow)
        await drainPresentationQueue()
        XCTAssertEqual(replacementWindow.presentationCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    func testReleasingThePresenterCancelsQueuedPresentation() async {
        var activationCount = 0
        let window = makeWindow()
        var presenter: SettingsWindowPresenter? = SettingsWindowPresenter(
            activateApplication: { activationCount += 1 }
        )
        weak var releasedPresenter: SettingsWindowPresenter?
        releasedPresenter = presenter
        presenter?.attach(window)
        presenter?.open(using: {})
        presenter = nil
        await drainPresentationQueue()

        XCTAssertNil(releasedPresenter)
        XCTAssertEqual(window.presentationCount, 0)
        XCTAssertEqual(activationCount, 0)
    }

    func testRemovingTheObserverDetachesItsRetainedWindow() async {
        var activationCount = 0
        let presenter = SettingsWindowPresenter(activateApplication: { activationCount += 1 })
        let previousWindow = makeWindow()
        let observer = SettingsWindowRegistration.WindowObserver()
        observer.presenter = presenter
        previousWindow.contentView?.addSubview(observer)
        observer.removeFromSuperview()

        presenter.open(using: {})
        await drainPresentationQueue()
        XCTAssertEqual(previousWindow.presentationCount, 0)
        XCTAssertEqual(activationCount, 0)

        let replacementWindow = makeWindow()
        replacementWindow.contentView?.addSubview(observer)
        await drainPresentationQueue()

        XCTAssertEqual(replacementWindow.presentationCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    func testMovingTheObserverPresentsItsNewWindow() async {
        let presenter = SettingsWindowPresenter(activateApplication: {})
        let previousWindow = makeWindow()
        let replacementWindow = makeWindow()
        let observer = SettingsWindowRegistration.WindowObserver()
        observer.presenter = presenter
        previousWindow.contentView?.addSubview(observer)
        presenter.open(using: {})

        replacementWindow.contentView?.addSubview(observer)
        await drainPresentationQueue()

        XCTAssertEqual(previousWindow.presentationCount, 0)
        XCTAssertEqual(replacementWindow.presentationCount, 1)
    }

    private func makeWindow() -> WindowSpy {
        _ = NSApplication.shared
        let window = WindowSpy(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func drainPresentationQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private final class WindowSpy: NSWindow {
        var presentationCount = 0
        var simulatesMiniaturization = false
        var onRestoration: (() -> Void)?
        var onPresentation: (() -> Void)?

        override var isMiniaturized: Bool { simulatesMiniaturization }

        override func deminiaturize(_ sender: Any?) {
            simulatesMiniaturization = false
            onRestoration?()
        }

        override func makeKeyAndOrderFront(_ sender: Any?) {
            presentationCount += 1
            onPresentation?()
        }
    }
}
