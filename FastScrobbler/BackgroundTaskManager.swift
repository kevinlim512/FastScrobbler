import BackgroundTasks
import Foundation
import OSLog

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

final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    private let logger = Logger(subsystem: "FastScrobbler", category: "BackgroundTasks")
    private var isRegistered = false

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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundTaskIdentifiers.appRefresh)
            try BGTaskScheduler.shared.submit(request)
            logger.debug("scheduled BGAppRefreshTask")
        } catch {
            logger.warning("failed to schedule BGAppRefreshTask: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        // Always reschedule, since iOS schedules are one-shot.
        scheduleAppRefresh()

        runBGTask(task, softTimeoutSeconds: 20) {
            await AppModel.shared.backgroundTick()
        }
    }

    func scheduleProcessingIfNeeded() {
        Task {
            let pending = await ScrobbleBacklog.shared.pendingCount()
            if pending > 0 {
                self.scheduleProcessing()
            } else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundTaskIdentifiers.processing)
            }
        }
    }

    private func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskIdentifiers.processing)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundTaskIdentifiers.processing)
            try BGTaskScheduler.shared.submit(request)
            logger.debug("scheduled BGProcessingTask")
        } catch {
            logger.warning("failed to schedule BGProcessingTask: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleProcessing(_ task: BGProcessingTask) {
        // Always reschedule, since iOS schedules are one-shot.
        scheduleProcessingIfNeeded()

        runBGTask(task, softTimeoutSeconds: 120) {
            await AppModel.shared.backgroundTick()
        }
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
            task.setTaskCompleted(success: !workTask.isCancelled)
        }
    }
}
