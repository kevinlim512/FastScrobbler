import Foundation
import SwiftUI

#if os(iOS)
import MessageUI
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum SupportEmailKind: String, Identifiable {
    case feedback
    case bugReport

    var id: String { rawValue }
}

struct SupportEmailSetting {
    let label: String
    let value: String
}

struct SupportEmailContext {
    let platformName: String
    let isProEnabled: Bool
    let isLastFMConnected: Bool
    let settings: [SupportEmailSetting]
}

struct SupportEmailAttachment {
    let fileName: String
    let mimeType: String
    let data: Data

    func writeTemporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FastScrobblerSupport",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        try data.write(to: url, options: .atomic)
        return url
    }
}

struct SupportEmailDraft: Identifiable {
    static let recipient = "fastscrobbler@gmail.com"
    static let bugReportFileName = "FastScrobbler Bug Report.txt"

    let kind: SupportEmailKind
    let subject: String
    let body: String
    let attachment: SupportEmailAttachment?

    var id: String {
        let attachmentID = attachment?.fileName ?? "none"
        return "\(kind.rawValue)-\(subject)-\(attachmentID)"
    }

    static func make(kind: SupportEmailKind, context: SupportEmailContext) -> SupportEmailDraft {
        switch kind {
        case .feedback:
            return SupportEmailDraft(
                kind: .feedback,
                subject: "FastScrobbler Feedback",
                body: "",
                attachment: nil
            )
        case .bugReport:
            return SupportEmailDraft(
                kind: .bugReport,
                subject: "FastScrobbler Bug Report",
                body: SupportEmailDiagnostics.bugReportBody,
                attachment: SupportEmailAttachment(
                    fileName: Self.bugReportFileName,
                    mimeType: "text/plain",
                    data: Data(SupportEmailDiagnostics.bugReportText(context: context).utf8)
                )
            )
        }
    }
}

enum SupportEmailError: LocalizedError {
    case unavailable
    case preparationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Mail isn't available right now. Please make sure Mail is installed and configured on this device."
        case .preparationFailed:
            return "Couldn't prepare the support email."
        }
    }
}

enum SupportEmailDiagnostics {
    static let bugReportBody = """
    What is the bug you’re reporting:

    How to reproduce the bug (if possible):

    """

    static func bugReportText(context: SupportEmailContext) -> String {
        let appInfoLines = [
            "App version: \(appVersion)",
            "Build number: \(buildNumber)",
            "Platform: \(context.platformName)",
            "OS version: \(osVersion)",
            "Pro enabled: \(yesNo(context.isProEnabled))",
            "Last.fm connected: \(yesNo(context.isLastFMConnected))",
        ]

        let settingsLines = context.settings.map { "- \($0.label): \($0.value)" }

        return """
        App Info:
        \(appInfoLines.map { "- \($0)" }.joined(separator: "\n"))

        Current Settings:
        \(settingsLines.joined(separator: "\n"))
        """
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}

#if os(iOS)
enum SupportEmailMailCompose {
    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }
}

struct SupportEmailComposeView: UIViewControllerRepresentable {
    let draft: SupportEmailDraft
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([SupportEmailDraft.recipient])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)

        if let attachment = draft.attachment {
            controller.addAttachmentData(
                attachment.data,
                mimeType: attachment.mimeType,
                fileName: attachment.fileName
            )
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            onFinish()
        }
    }
}
#elseif os(macOS)
@MainActor
enum SupportEmailMailCompose {
    static func compose(_ draft: SupportEmailDraft) throws {
        let items = try sharingItems(for: draft)
        guard let service = NSSharingService(named: .composeEmail),
              service.canPerform(withItems: items) else {
            throw SupportEmailError.unavailable
        }

        service.recipients = [SupportEmailDraft.recipient]
        service.subject = draft.subject
        service.perform(withItems: items)
    }

    private static func sharingItems(for draft: SupportEmailDraft) throws -> [Any] {
        if let attachment = draft.attachment {
            return [draft.body, try attachment.writeTemporaryFile()]
        }

        return [draft.body]
    }
}
#endif
