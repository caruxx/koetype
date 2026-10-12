/// Maps an observed delivery state to passive feedback. Unknown AX results must
/// never be shown as an insertion failure or cause a second paste.
public enum DeliveryPresentation {
    public static let manualCopyTitle = "直前の文字起こしをコピー"

    public struct Notice: Equatable, Sendable {
        public let text: String
        public let isWarning: Bool

        public init(text: String, isWarning: Bool) {
            self.text = text
            self.isWarning = isWarning
        }
    }

    public static func copyLatest(from memory: LatestDeliveryMemory, toClipboard: (String) -> Void) {
        guard let text = memory.latestText else { return }
        toClipboard(text)
    }

    public static func outcome(plan: InsertionPlan, didPaste: Bool,
                               verification: InsertionVerification.Result?) -> DeliveryOutcome {
        if plan == .copyBoxOnly { return .copyBox }
        if !didPaste { return .notPasted }
        return verification == .confirmed ? .inserted : .unverified
    }

    public static func copyBoxMessage(outcome: DeliveryOutcome,
                                      verification: InsertionVerification.Result?) -> String? {
        if outcome == .copyBox { return "入力欄が見つからなかったため、ここに表示しています" }
        if outcome == .notPasted && verification == .dispatchFailed {
            return "貼り付けを開始できませんでした。ここからコピーできます"
        }
        return nil
    }

    public static func indicatorMessage(outcome: DeliveryOutcome, blockingWarning: Bool = false) -> String? {
        if blockingWarning { return nil }
        switch outcome {
        case .unverified: return "入力未確認"
        case .notPasted: return "貼り付けませんでした。メニューからコピーできます"
        case .inserted, .copyBox, .insertedAndCopyBox: return nil
        }
    }

    public static func notice(for status: PipelineStatus, blockingWarning: Bool) -> Notice? {
        switch status {
        case .delivered(let outcome, _):
            return indicatorMessage(outcome: outcome, blockingWarning: blockingWarning)
                .map { Notice(text: $0, isWarning: false) }
        case .nothingHeard: return Notice(text: "聞き取れませんでした", isWarning: false)
        case .failed(let text): return Notice(text: text, isWarning: false)
        case .warning(let text): return Notice(text: text, isWarning: true)
        case .transcribing, .polishing: return nil
        }
    }
}

/// Tracks only the short on-screen notice. A history warning blocks routine
/// delivery feedback, while a later explicit failure can replace it.
public struct DeliveryNoticeState: Equatable, Sendable {
    public private(set) var current: DeliveryPresentation.Notice?

    public init() {}

    public mutating func present(_ notice: DeliveryPresentation.Notice) {
        current = notice
    }

    public mutating func advance(_ status: PipelineStatus) -> DeliveryPresentation.Notice? {
        guard let notice = DeliveryPresentation.notice(for: status,
                                                       blockingWarning: current?.isWarning == true) else { return nil }
        current = notice
        return notice
    }

    public mutating func clear() { current = nil }
}
