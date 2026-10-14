import Foundation
import OSLog

struct DiagnosticRouter: DiagnosticRecording {
    private let recorders: [any DiagnosticRecording]

    init(_ recorders: [any DiagnosticRecording]) {
        self.recorders = recorders
    }

    func record(_ event: DiagnosticEvent) {
        recorders.forEach { $0.record(event) }
    }
}

struct UnifiedLogSink: DiagnosticRecording {
    private let subsystem = Bundle.main.bundleIdentifier ?? "com.abel.primarypaste"

    func record(_ event: DiagnosticEvent) {
        guard event.audience.includesDevelopers else { return }
        let logger = Logger(subsystem: subsystem, category: event.capability.rawValue)
        let metadata = event.metadata.publicSummary
        let detail = event.metadata.privateSystemDetail ?? "none"

        switch event.severity {
        case .debug:
            logger.debug(
                "event=\(event.code, privacy: .public) outcome=\(event.outcome.rawValue, privacy: .public) metadata=\(metadata, privacy: .public) detail=\(detail, privacy: .private)"
            )
        case .info:
            logger.info(
                "event=\(event.code, privacy: .public) outcome=\(event.outcome.rawValue, privacy: .public) metadata=\(metadata, privacy: .public) detail=\(detail, privacy: .private)"
            )
        case .notice:
            logger.notice(
                "event=\(event.code, privacy: .public) outcome=\(event.outcome.rawValue, privacy: .public) metadata=\(metadata, privacy: .public) detail=\(detail, privacy: .private)"
            )
        case .error:
            logger.error(
                "event=\(event.code, privacy: .public) outcome=\(event.outcome.rawValue, privacy: .public) metadata=\(metadata, privacy: .public) detail=\(detail, privacy: .private)"
            )
        case .fault:
            logger.fault(
                "event=\(event.code, privacy: .public) outcome=\(event.outcome.rawValue, privacy: .public) metadata=\(metadata, privacy: .public) detail=\(detail, privacy: .private)"
            )
        }
    }
}

final class SupportDiagnosticsSink: DiagnosticRecording {
    private weak var diagnostics: InteractionDiagnostics?

    init(diagnostics: InteractionDiagnostics) {
        self.diagnostics = diagnostics
    }

    func record(_ event: DiagnosticEvent) {
        diagnostics?.storeForSupport(event)
    }
}
