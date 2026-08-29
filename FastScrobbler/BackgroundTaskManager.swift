import BackgroundTasks
import Foundation
import OSLog
#if os(iOS)
import UIKit
#endif

enum BackgroundTaskIdentifiers {
    static var appRefresh: String {
        // Must match the value in `Info.plist` BGTaskSchedulerPermittedIdentifiers.
        (Bundle.main.bundleIdentifier ?? "com.example.FastScrobbler") + ".appRefresh"
    }

    static var processing: String {
        // Must match the value in `Info.plist` BGTaskSchedulerPermittedIdentifiers.
        (Bundle.main.bundleIdentifier ?? "com.example.FastScrobbler") + ".processing"
    }
}

#if os(iOS)
private final class BackgroundTaskIdentifierBox: @unchecked Sendable {
    var value: UIBackgroundTaskIdentifier = .invalid
}
#endif

final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    private let logger = Logger(subsystem: "FastScrobbler", category: "BackgroundTasks")
    private var isRegistered = false
#if os(iOS)
    private static let liveScrobbleExpirationSafetyMarginSeconds: TimeInterval = 2
    private var liveScrobbleGraceTaskID: UIBackgroundTaskIdentifier = .invalid
    private var liveScrobbleGraceDidExpire = false
    private var liveScrobbleGraceProjectionAttempted = false
    private var liveScrobbleGraceStartedAt: Date?
    private var liveScrobbleGraceOnExpired: (@MainActor () async -> Void)?
#endif

    private init() {}

    func registerIfNeeded() {
        guard !isRegistered else { return }
        isRegistered = true

        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTaskIdentifiers.appRefresh, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleAppRefresh(task)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTaskIdentifiers.processing, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleProcessing(task)
        }
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskIdentifiers.appRefresh)
        request.earliestBeginDate = nil // Let iOS decide; don't impose extra delay

        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundTaskIdentifiers.appRefresh)
            try BGTaskScheduler.shared.submit(request)
            logger.debug("scheduled BGAppRefreshTask")
        } catch {
            logger.warning("failed to schedule BGAppRefreshTask: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        logger.info("BGAppRefreshTask handler fired")
        // Always reschedule, since iOS schedules are one-shot.
        scheduleAppRefresh()

        runBGTask(task, softTimeoutSeconds: 25) {
            await AppModel.shared.performScheduledBackgroundRecovery()
        }
    }

    func scheduleProcessingIfNeeded() {
        Task { @MainActor in
            let pending = await ScrobbleBacklog.shared.pendingCount()
            if Self.shouldScheduleProcessing(pendingCount: pending) {
                self.scheduleProcessing()
            } else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundTaskIdentifiers.processing)
            }
        }
    }

    func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskIdentifiers.processing)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = nil // Let iOS decide; don't impose extra delay

        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundTaskIdentifiers.processing)
            try BGTaskScheduler.shared.submit(request)
            logger.debug("scheduled BGProcessingTask")
        } catch {
            logger.warning("failed to schedule BGProcessingTask: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleProcessing(_ task: BGProcessingTask) {
        logger.info("BGProcessingTask handler fired")
        // Always reschedule, since iOS schedules are one-shot.
        scheduleProcessingIfNeeded()

        runBGTask(task, softTimeoutSeconds: 120) {
            await AppModel.shared.performScheduledBackgroundRecovery()
        }
    }

    static func shouldScheduleProcessing(pendingCount: Int) -> Bool {
        pendingCount > 0
    }

    private func runBGTask(_ task: BGTask, softTimeoutSeconds: TimeInterval, work: @escaping @MainActor () async -> Void) {
        let workTask = Task { @MainActor in
            await work()
        }

        task.expirationHandler = {
            workTask.cancel()
        }

        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, softTimeoutSeconds) * 1_000_000_000))
                workTask.cancel()
            } catch {
                // Ignore cancellation.
            }
        }

        Task {
            _ = await workTask.result
            timeoutTask.cancel()
            let cancelled = workTask.isCancelled
            logger.info("BGTask completed — success: \(!cancelled)")
            task.setTaskCompleted(success: !cancelled)
        }
    }

#if os(iOS)
    @MainActor
    func startLiveScrobbleGracePeriod(onExpired: @escaping @MainActor () async -> Void) -> Bool {
        endLiveScrobbleGracePeriod()

        liveScrobbleGraceDidExpire = false
        liveScrobbleGraceProjectionAttempted = false
        liveScrobbleGraceStartedAt = Date()
        liveScrobbleGraceOnExpired = onExpired

        let taskIDBox = BackgroundTaskIdentifierBox()
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "FastScrobbler.LiveScrobbleGrace") { [weak self] in
            self?.expireLiveScrobbleGracePeriodFromSystemExpiration(taskID: taskIDBox.value)
        }
        taskIDBox.value = taskID

        guard taskID != .invalid else {
            liveScrobbleGraceOnExpired = nil
            liveScrobbleGraceStartedAt = nil
            logger.warning("failed to start live scrobble grace period")
            return false
        }

        liveScrobbleGraceTaskID = taskID

        logger.info("started live scrobble grace period")
        return true
    }

    @MainActor
    func endLiveScrobbleGracePeriod() {
        liveScrobbleGraceOnExpired = nil
        liveScrobbleGraceDidExpire = false
        liveScrobbleGraceProjectionAttempted = false
        liveScrobbleGraceStartedAt = nil

        guard liveScrobbleGraceTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(liveScrobbleGraceTaskID)
        liveScrobbleGraceTaskID = .invalid
        logger.info("ended live scrobble grace period")
    }

    @MainActor
    var isLiveScrobbleGracePeriodActive: Bool {
        liveScrobbleGraceTaskID != .invalid && !liveScrobbleGraceDidExpire
    }

    @MainActor
    func recordLiveScrobbleGraceProjectionAttempt() {
        guard liveScrobbleGraceTaskID != .invalid else { return }
        liveScrobbleGraceProjectionAttempted = true
    }

    @MainActor
    func expireLiveScrobbleGracePeriodBecauseBackgroundTimeIsNearlyExhausted(remaining: TimeInterval? = nil) async {
        await expireLiveScrobbleGracePeriod(
            reason: "background time nearly exhausted",
            remainingBackgroundTime: remaining
        )
    }

    @MainActor
    func expireLiveScrobbleGracePeriodBecausePlaybackIsNoLongerActive() async {
        await expireLiveScrobbleGracePeriod(reason: "playback no longer active")
    }

    @MainActor
    var liveScrobbleBackgroundTimeRemaining: TimeInterval {
        UIApplication.shared.backgroundTimeRemaining
    }

    @MainActor
    private func expireLiveScrobbleGracePeriod(
        reason: StaticString,
        remainingBackgroundTime: TimeInterval? = nil
    ) async {
        guard liveScrobbleGraceTaskID != .invalid || liveScrobbleGraceOnExpired != nil else { return }
        guard !liveScrobbleGraceDidExpire else { return }

        liveScrobbleGraceDidExpire = true

        let onExpired = liveScrobbleGraceOnExpired
        liveScrobbleGraceOnExpired = nil

        logLiveScrobbleGraceExpirationSummary(reason: reason, remainingBackgroundTime: remainingBackgroundTime)

        if liveScrobbleGraceTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(liveScrobbleGraceTaskID)
            liveScrobbleGraceTaskID = .invalid
        }

        await onExpired?()
        liveScrobbleGraceDidExpire = false
        liveScrobbleGraceProjectionAttempted = false
        liveScrobbleGraceStartedAt = nil
    }

    private func expireLiveScrobbleGracePeriodFromSystemExpiration(taskID: UIBackgroundTaskIdentifier) {
        guard taskID != .invalid else { return }
        Task { @MainActor [weak self] in
            guard let self else {
                UIApplication.shared.endBackgroundTask(taskID)
                return
            }
            guard self.liveScrobbleGraceTaskID == taskID else {
                UIApplication.shared.endBackgroundTask(taskID)
                return
            }
            guard !self.liveScrobbleGraceDidExpire else {
                UIApplication.shared.endBackgroundTask(taskID)
                self.liveScrobbleGraceTaskID = .invalid
                return
            }

            self.liveScrobbleGraceDidExpire = true

            let onExpired = self.liveScrobbleGraceOnExpired
            self.liveScrobbleGraceOnExpired = nil

            let remaining = UIApplication.shared.backgroundTimeRemaining
            self.logLiveScrobbleGraceExpirationSummary(
                reason: "system expiration",
                remainingBackgroundTime: remaining.isFinite ? remaining : nil
            )
            UIApplication.shared.endBackgroundTask(taskID)
            self.liveScrobbleGraceTaskID = .invalid

            await onExpired?()
            self.liveScrobbleGraceDidExpire = false
            self.liveScrobbleGraceProjectionAttempted = false
            self.liveScrobbleGraceStartedAt = nil
        }
    }

    private func logLiveScrobbleGraceExpirationSummary(
        reason: StaticString,
        remainingBackgroundTime: TimeInterval?
    ) {
        if let remainingBackgroundTime {
            logger.info(
                "expiring live scrobble grace period: \(reason, privacy: .public) (remaining: \(remainingBackgroundTime, privacy: .public)s, projectionAttempted: \(self.liveScrobbleGraceProjectionAttempted, privacy: .public))"
            )
        } else {
            logger.info(
                "expiring live scrobble grace period: \(reason, privacy: .public) (projectionAttempted: \(self.liveScrobbleGraceProjectionAttempted, privacy: .public))"
            )
        }
    }
#endif
}
