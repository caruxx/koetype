import XCTest
@testable import KoeTypeCore

private final class FakeTranscriber: Transcribing, @unchecked Sendable {
    var results: [Result<String, Error>] = []
    var delays: [Double] = []
    private(set) var hints: [String] = []
    private let lock = NSLock()

    func transcribe(samples: [Float], hints: String) async throws -> String {
        let (result, delay): (Result<String, Error>, Double) = lock.withLock {
            self.hints.append(hints)
            return (results.removeFirst(), delays.isEmpty ? 0 : delays.removeFirst())
        }
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return try result.get()
    }
}

private final class FakePolisher: Polishing, @unchecked Sendable {
    var handler: (String) throws -> String = { $0 + "。" }
    private(set) var calls = 0
    private(set) var styles: [PolishStyle] = []
    private(set) var inputs: [String] = []
    func polish(raw: String, dictionary: [DictionaryEntry], style: PolishStyle) async throws -> String {
        calls += 1
        styles.append(style)
        inputs.append(raw)
        return try handler(raw)
    }
}

private final class FakeDeliverer: TextDelivering, @unchecked Sendable {
    var outcome: DeliveryOutcome = .inserted
    var latestMemory: LatestDeliveryMemory?
    private(set) var delivered: [String] = []
    func deliver(_ text: String) async -> DeliveryResult {
        delivered.append(text)
        latestMemory?.remember(text)
        return DeliveryResult(outcome: outcome, appName: "メモ")
    }
}

private final class StatusLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [PipelineStatus] = []
    func add(_ status: PipelineStatus) { lock.withLock { values.append(status) } }
    var all: [PipelineStatus] { lock.withLock { values } }
}

private struct Boom: Error {}

final class DictationPipelineTests: XCTestCase {
    private var dir: URL!
    private var transcriber: FakeTranscriber!
    private var polisher: FakePolisher!
    private var deliverer: FakeDeliverer!
    private var dictionary: DictionaryStore!
    private var history: HistoryStore!
    private var log: StatusLog!
    private var polishEnabled = true
    private var minimumAICharacters = 0

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        transcriber = FakeTranscriber(); polisher = FakePolisher(); deliverer = FakeDeliverer()
        dictionary = DictionaryStore(fileURL: dir.appendingPathComponent("dictionary.json"))
        history = HistoryStore(fileURL: dir.appendingPathComponent("history.json"))
        log = StatusLog(); polishEnabled = true; minimumAICharacters = 0
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func makePipeline() -> DictationPipeline {
        let enabled = polishEnabled
        let minimum = minimumAICharacters
        let log = self.log!
        return DictationPipeline(transcriber: transcriber, polisher: polisher, deliverer: deliverer,
                                 dictionary: dictionary, history: history,
                                 polishEnabled: { enabled },
                                 minimumAICharacters: { minimum },
                                 styleFor: { AppStyleRules(overrides: [:]).style(forBundleID: $0) },
                                 now: { Date(timeIntervalSince1970: 100) },
                                 onStatus: { log.add($0) })
    }

    func testHappyPathPolishesDeliversAndRecords() async throws {
        try dictionary.add(term: "ASIN", variants: [], now: Date())
        transcriber.results = [.success(" えーと明日は休みです ")]
        await makePipeline().submit(samples: [0.1], durationSeconds: 2.5).value

        XCTAssertEqual(transcriber.hints, ["ASIN"])
        XCTAssertEqual(deliverer.delivered, ["明日は休みです。"])
        XCTAssertEqual(log.all, [.transcribing, .polishing, .delivered(.inserted, polished: true)])
        let item = try XCTUnwrap(history.items.first)
        XCTAssertEqual(item.rawText, "えーと明日は休みです")
        XCTAssertEqual(item.finalText, "明日は休みです。")
        XCTAssertEqual(item.appName, "メモ")
        XCTAssertEqual(item.outcome, .inserted)
        XCTAssertTrue(item.polished)
        XCTAssertEqual(item.durationSeconds, 2.5)
        XCTAssertEqual(item.date, Date(timeIntervalSince1970: 100))
    }

    func testPolishFailureFallsBackToRaw() async {
        transcriber.results = [.success("明日は休みです")]
        polisher.handler = { _ in throw PolishError.timeout }
        deliverer.outcome = .copyBox
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value

        XCTAssertEqual(deliverer.delivered, ["明日は休みです"])
        XCTAssertEqual(history.items.first?.polished, false)
        XCTAssertEqual(history.items.first?.outcome, .copyBox)
        XCTAssertEqual(log.all.last, .delivered(.copyBox, polished: false))
    }

    func testUnverifiedDeliveryStaysUnverifiedInHistoryAndStatus() async {
        polishEnabled = false
        transcriber.results = [.success("短い文")]
        deliverer.outcome = .unverified
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertEqual(deliverer.delivered, ["短い文"])
        XCTAssertEqual(history.items.first?.outcome, .unverified)
        XCTAssertEqual(log.all.last, .delivered(.unverified, polished: false))
    }

    func testPreflightFailureStaysNotPastedInHistoryAndStatus() async {
        polishEnabled = false
        transcriber.results = [.success("短い文")]
        deliverer.outcome = .notPasted
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertEqual(history.items.first?.outcome, .notPasted)
        XCTAssertEqual(log.all.last, .delivered(.notPasted, polished: false))
    }

    func testRejectedPolishResultFallsBackToRaw() async {
        transcriber.results = [.success("はい")]
        polisher.handler = { _ in "はい、承知しました。ご質問にお答えします。明日の天気は晴れです。" }
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertEqual(deliverer.delivered, ["はい"])
        XCTAssertEqual(history.items.first?.polished, false)
    }

    func testPolishDisabledSkipsPolisher() async {
        polishEnabled = false
        transcriber.results = [.success("明日は休みです")]
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertEqual(polisher.calls, 0)
        XCTAssertEqual(deliverer.delivered, ["明日は休みです"])
        XCTAssertEqual(log.all, [.transcribing, .delivered(.inserted, polished: false)])
    }

    func testPhantomPhraseDeliversNothing() async {
        transcriber.results = [.success("ご視聴ありがとうございました")]
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertTrue(deliverer.delivered.isEmpty)
        XCTAssertTrue(history.items.isEmpty)
        XCTAssertEqual(polisher.calls, 0)
        XCTAssertEqual(log.all, [.transcribing, .nothingHeard])
    }

    func testTranscriptionErrorReportsFailure() async {
        transcriber.results = [.failure(Boom())]
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertTrue(deliverer.delivered.isEmpty)
        XCTAssertEqual(log.all, [.transcribing, .failed("文字起こしに失敗しました")])
    }

    func testRecordingsAreDeliveredInSubmissionOrder() async {
        polishEnabled = false
        transcriber.results = [.success("一つ目"), .success("二つ目"), .success("三つ目")]
        transcriber.delays = [0.2, 0, 0]
        let pipeline = makePipeline()
        let first = pipeline.submit(samples: [0.1], durationSeconds: 1)
        let second = pipeline.submit(samples: [0.2], durationSeconds: 1)
        let third = pipeline.submit(samples: [0.3], durationSeconds: 1)
        await first.value; await second.value; await third.value
        XCTAssertEqual(deliverer.delivered, ["一つ目", "二つ目", "三つ目"])
    }

    func testFailureDoesNotBlockTheNextRecording() async {
        polishEnabled = false
        transcriber.results = [.failure(Boom()), .success("次の発話")]
        let pipeline = makePipeline()
        let first = pipeline.submit(samples: [0.1], durationSeconds: 1)
        let second = pipeline.submit(samples: [0.2], durationSeconds: 1)
        await first.value; await second.value
        XCTAssertEqual(deliverer.delivered, ["次の発話"])
    }

    func testHistorySaveFailureIsReportedButTextIsStillDelivered() async throws {
        let memory = LatestDeliveryMemory()
        deliverer.latestMemory = memory
        deliverer.outcome = .unverified
        let url = dir.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        history = HistoryStore(fileURL: url)
        polishEnabled = false
        transcriber.results = [.success("明日は休みです")]

        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value

        XCTAssertEqual(deliverer.delivered, ["明日は休みです"])
        XCTAssertTrue(history.items.isEmpty)
        XCTAssertEqual(memory.latestText, "明日は休みです")
        var copied: [String] = []
        DeliveryPresentation.copyLatest(from: memory) { copied.append($0) }
        XCTAssertEqual(copied, ["明日は休みです"])
        XCTAssertEqual(log.all, [.transcribing, .warning("履歴を保存できませんでした"),
                                 .delivered(.unverified, polished: false)])
        XCTAssertNil(DeliveryPresentation.indicatorMessage(outcome: .unverified, blockingWarning: true))
    }

    func testHistorySaveFailureWithOlderItemStillCopiesCurrentNotPastedText() async throws {
        let memory = LatestDeliveryMemory()
        deliverer.latestMemory = memory
        deliverer.outcome = .notPasted
        let url = dir.appendingPathComponent("history.json")
        history = HistoryStore(fileURL: url)
        try history.append(HistoryItem(date: Date(timeIntervalSince1970: 1), rawText: "old",
                                       finalText: "old", appName: nil, outcome: .inserted,
                                       polished: false, durationSeconds: 1))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        polishEnabled = false
        transcriber.results = [.success("new")]

        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value

        XCTAssertEqual(history.items.first?.finalText, "old")
        XCTAssertEqual(memory.latestText, "new")
        var copied: [String] = []
        DeliveryPresentation.copyLatest(from: memory) { copied.append($0) }
        XCTAssertEqual(copied, ["new"])
        XCTAssertEqual(log.all, [.transcribing, .warning("履歴を保存できませんでした"),
                                 .delivered(.notPasted, polished: false)])
        XCTAssertNil(DeliveryPresentation.indicatorMessage(outcome: .notPasted, blockingWarning: true))
    }

    func testHistorySaveFailureWithoutOlderItemStillCopiesCurrentNotPastedText() async throws {
        let memory = LatestDeliveryMemory()
        deliverer.latestMemory = memory
        deliverer.outcome = .notPasted
        let url = dir.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        history = HistoryStore(fileURL: url)
        polishEnabled = false
        transcriber.results = [.success("new")]

        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value

        XCTAssertTrue(history.items.isEmpty)
        var copied: [String] = []
        DeliveryPresentation.copyLatest(from: memory) { copied.append($0) }
        XCTAssertEqual(copied, ["new"])
        XCTAssertEqual(log.all, [.transcribing, .warning("履歴を保存できませんでした"),
                                 .delivered(.notPasted, polished: false)])
        XCTAssertNil(DeliveryPresentation.indicatorMessage(outcome: .notPasted, blockingWarning: true))
    }

    func testHistorySaveFailureWithOlderItemStillCopiesCurrentUnverifiedText() async throws {
        let memory = LatestDeliveryMemory()
        deliverer.latestMemory = memory
        deliverer.outcome = .unverified
        let url = dir.appendingPathComponent("history.json")
        history = HistoryStore(fileURL: url)
        try history.append(HistoryItem(date: Date(timeIntervalSince1970: 1), rawText: "old",
                                       finalText: "old", appName: nil, outcome: .inserted,
                                       polished: false, durationSeconds: 1))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        polishEnabled = false
        transcriber.results = [.success("new")]

        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value

        XCTAssertEqual(history.items.first?.finalText, "old")
        var copied: [String] = []
        DeliveryPresentation.copyLatest(from: memory) { copied.append($0) }
        XCTAssertEqual(copied, ["new"])
        XCTAssertEqual(log.all, [.transcribing, .warning("履歴を保存できませんでした"),
                                 .delivered(.unverified, polished: false)])
        XCTAssertNil(DeliveryPresentation.indicatorMessage(outcome: .unverified, blockingWarning: true))
    }

    func testShortUtteranceIsFinishedLocallyWithoutAI() async {
        minimumAICharacters = 20
        transcriber.results = [.success("えーと、了解です。")]
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertEqual(polisher.calls, 0)
        XCTAssertEqual(deliverer.delivered, ["了解です。"])
        XCTAssertEqual(history.items.first?.rawText, "えーと、了解です。")
        XCTAssertEqual(history.items.first?.polished, false)
        XCTAssertEqual(log.all, [.transcribing, .delivered(.inserted, polished: false)])
    }

    func testLongUtteranceGoesToAIWhenEnabled() async {
        minimumAICharacters = 20
        transcriber.results = [.success("来週の火曜日の午後3時から打ち合わせをお願いします")]
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertEqual(polisher.calls, 1)
        XCTAssertEqual(deliverer.delivered, ["来週の火曜日の午後3時から打ち合わせをお願いします。"])
    }

    func testAIFailureFallsBackToTheLocallyCleanedText() async {
        transcriber.results = [.success("えーと、来週の火曜日の午後3時から打ち合わせをお願いします。")]
        polisher.handler = { _ in throw PolishError.timeout }
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertEqual(deliverer.delivered, ["来週の火曜日の午後3時から打ち合わせをお願いします。"])
    }

    func testAIDisabledStillRemovesFillersLocally() async {
        polishEnabled = false
        transcriber.results = [.success("あのー、明日は休みです。")]
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertEqual(deliverer.delivered, ["明日は休みです。"])
    }

    func testOnlyFillersDeliversNothing() async {
        transcriber.results = [.success("えーと。")]
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertTrue(deliverer.delivered.isEmpty)
        XCTAssertEqual(log.all, [.transcribing, .nothingHeard])
    }

    func testStyleFollowsTheAppThatReceivesTheText() async {
        transcriber.results = [.success("来週の火曜日の午後3時から打ち合わせをお願いします"),
                               .success("来週の火曜日の午後3時から打ち合わせをお願いします")]
        let pipeline = makePipeline()
        await pipeline.submit(samples: [0.1], durationSeconds: 1, appBundleID: "com.tinyspeck.slackmacgap").value
        await pipeline.submit(samples: [0.1], durationSeconds: 1, appBundleID: "com.apple.mail").value
        XCTAssertEqual(polisher.styles, [.chat, .mail])
    }

    func testMinimalStyleAppsNeverCallTheModel() async {
        transcriber.results = [.success("えーと、来週の火曜日の午後3時から打ち合わせをお願いします。")]
        await makePipeline().submit(samples: [0.1], durationSeconds: 1, appBundleID: "com.apple.Terminal").value
        XCTAssertEqual(polisher.calls, 0)
        XCTAssertEqual(deliverer.delivered, ["来週の火曜日の午後3時から打ち合わせをお願いします。"])
    }

    func testChatAppsGetNoFinalFullStop() async {
        transcriber.results = [.success("来週の火曜日の午後3時から打ち合わせをお願いします")]
        await makePipeline().submit(samples: [0.1], durationSeconds: 1, appBundleID: "jp.naver.line.mac").value
        XCTAssertEqual(deliverer.delivered, ["来週の火曜日の午後3時から打ち合わせをお願いします"])
    }

    func testModelReceivesLocallyCleanedTextAndItsOutputIsCleanedAgain() async {
        transcriber.results = [.success("えーと、来週の火曜日の午後3時から打ち合わせをお願いします。")]
        // Measured: the on-device model sometimes puts fillers back.
        polisher.handler = { input in "えっと、" + input }
        await makePipeline().submit(samples: [0.1], durationSeconds: 1).value
        XCTAssertEqual(polisher.inputs, ["来週の火曜日の午後3時から打ち合わせをお願いします。"])
        XCTAssertEqual(deliverer.delivered, ["来週の火曜日の午後3時から打ち合わせをお願いします。"])
        XCTAssertEqual(history.items.first?.rawText, "えーと、来週の火曜日の午後3時から打ち合わせをお願いします。")
    }
}
