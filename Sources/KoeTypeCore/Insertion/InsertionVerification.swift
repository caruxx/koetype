import Foundation

public enum InsertionVerification {
    public enum Result: String, Equatable, Sendable {
        case confirmed, unverified, targetChanged, dispatchFailed
    }

    /// The AX adapter supplies identity and editability checks, not just a value.
    public enum Sample: Equatable, Sendable {
        case field(value: String?, selection: InsertionSelection?, sameApp: Bool,
                   sameElement: Bool, snapshot: FocusSnapshot)
        case temporarilyUnavailable
    }

    public struct Attempt: Equatable, Sendable {
        public let result: Result
        public let didPaste: Bool
    }

    /// Check the target immediately before dispatching the paste, then paste at most once.
    @MainActor public static func pasteAndVerify(
        valueBefore: String, selection: InsertionSelection, insertedText: String, attempts: Int = 10,
        intervalNanoseconds: UInt64 = 100_000_000,
        paste: () -> Bool, observe: () async -> Sample
    ) async -> Attempt {
        switch await observe() {
        case .field(let value, let currentSelection, let sameApp, let sameElement, let snapshot):
            guard sameApp && sameElement && InsertionDecision.canVerify(snapshot) else {
                return Attempt(result: .targetChanged, didPaste: false)
            }
            guard value == valueBefore && currentSelection == selection else {
                return Attempt(result: .unverified, didPaste: false)
            }
        case .temporarilyUnavailable:
            return Attempt(result: .unverified, didPaste: false)
        }

        guard paste() else { return Attempt(result: .dispatchFailed, didPaste: false) }
        for _ in 0..<attempts {
            if intervalNanoseconds > 0 { try? await Task.sleep(nanoseconds: intervalNanoseconds) }
            switch await observe() {
            case .field(let valueAfter, _, let sameApp, let sameElement, let snapshot):
                guard sameApp && sameElement && InsertionDecision.canVerify(snapshot) else {
                    return Attempt(result: .targetChanged, didPaste: true)
                }
                if InsertionDecision.didInsert(valueBefore: valueBefore, valueAfter: valueAfter,
                                               insertedText: insertedText, selection: selection) {
                    return Attempt(result: .confirmed, didPaste: true)
                }
            case .temporarilyUnavailable:
                continue
            }
        }
        return Attempt(result: .unverified, didPaste: true)
    }
}
