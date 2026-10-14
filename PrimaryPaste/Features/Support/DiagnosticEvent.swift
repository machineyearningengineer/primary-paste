import Foundation

protocol DiagnosticRecording {
    func record(_ event: DiagnosticEvent)
}

struct DiagnosticEvent: Identifiable, Equatable {
    enum Capability: String, CaseIterable {
        case app
        case input
        case paste
        case clipboard
        case permissions
        case privacy
        case selection
        case fileSelection = "file-selection"
        case licensing
    }

    enum Severity {
        case debug
        case info
        case notice
        case error
        case fault
    }

    enum Audience {
        case developers
        case support
        case both

        var includesDevelopers: Bool { self != .support }
        var includesSupport: Bool { self != .developers }
    }

    enum Outcome: String {
        case observed
        case succeeded
        case failed
        case recovered
        case skipped
    }

    struct Metadata: Equatable {
        var payloadType: String?
        var characterCount: Int?
        var itemCount: Int?
        var targetSurface: String?
        var errorCategory: String?
        var state: String?
        var privateSystemDetail: String?

        var publicSummary: String {
            [
                payloadType.map { "payload=\($0)" },
                characterCount.map { "characters=\($0)" },
                itemCount.map { "items=\($0)" },
                targetSurface.map { "surface=\($0)" },
                errorCategory.map { "error=\($0)" },
                state.map { "state=\($0)" },
            ]
            .compactMap { $0 }
            .joined(separator: ",")
        }

        var supportSafe: Metadata {
            var copy = self
            copy.privateSystemDetail = nil
            return copy
        }
    }

    let id: UUID
    let timestamp: Date
    let capability: Capability
    let severity: Severity
    let audience: Audience
    let outcome: Outcome
    let code: String
    let supportMessage: String?
    let metadata: Metadata

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        capability: Capability,
        severity: Severity = .info,
        audience: Audience = .both,
        outcome: Outcome = .observed,
        code: String,
        supportMessage: String? = nil,
        metadata: Metadata = Metadata()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.capability = capability
        self.severity = severity
        self.audience = audience
        self.outcome = outcome
        self.code = code
        self.supportMessage = supportMessage
        self.metadata = metadata
    }

    var supportSafe: DiagnosticEvent {
        DiagnosticEvent(
            id: id,
            timestamp: timestamp,
            capability: capability,
            severity: severity,
            audience: audience,
            outcome: outcome,
            code: code,
            supportMessage: supportMessage,
            metadata: metadata.supportSafe
        )
    }
}
