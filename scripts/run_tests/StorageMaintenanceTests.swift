import Foundation

@MainActor
func runStorageMaintenanceTests() async {
    section("Storage Maintenance · Migration gating")

    let currentMigrationVersion = 1

    func shouldRunStartupMaintenance(storedVersion: Int, currentVersion: Int = currentMigrationVersion) -> Bool {
        storedVersion < currentVersion
    }

    expect("startup maintenance runs when no migration has been recorded", shouldRunStartupMaintenance(storedVersion: 0))
    expect("startup maintenance skips once the current migration version is recorded", !shouldRunStartupMaintenance(storedVersion: currentMigrationVersion))
    expect("startup maintenance skips newer stored migration versions", !shouldRunStartupMaintenance(storedVersion: currentMigrationVersion + 1))

    section("Storage Maintenance · Real Store Byte Counting")

    let logStoreBytes = ScrobbleLogStore.shared.storageSizeBytes()
    expect("ScrobbleLogStore reports valid storage byte count", logStoreBytes >= 0, detail: "got \(logStoreBytes) bytes")

    let backlogBytes = await ScrobbleBacklog.shared.storageSizeBytes()
    expect("ScrobbleBacklog reports valid storage byte count", backlogBytes >= 0, detail: "got \(backlogBytes) bytes")
}


