import Foundation

final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    private init() {}

    func registerIfNeeded() {}

    func scheduleAppRefresh() {}

    func scheduleProcessingIfNeeded() {}
}

