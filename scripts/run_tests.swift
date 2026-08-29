#!/usr/bin/env swift
// Tests for the Priority 1 & 3 fixes.
// Run with: swift scripts/run_tests.swift

import Foundation

let fileManager = FileManager.default
let scriptPath = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: URL(fileURLWithPath: fileManager.currentDirectoryPath)).standardizedFileURL
let scriptsDirectory = scriptPath.deletingLastPathComponent()
let sourceDirectory = scriptsDirectory.appendingPathComponent("run_tests", isDirectory: true)

let allSources = try fileManager.contentsOfDirectory(
    at: sourceDirectory,
    includingPropertiesForKeys: nil
)
.filter { $0.pathExtension == "swift" }
.sorted { lhs, rhs in
    if lhs.lastPathComponent == "Main.swift" { return false }
    if rhs.lastPathComponent == "Main.swift" { return true }
    return lhs.lastPathComponent < rhs.lastPathComponent
}

let projectDirectory = scriptsDirectory.deletingLastPathComponent()
let sharedSources = [
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("Models", isDirectory: true)
        .appendingPathComponent("Track.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("LastFM", isDirectory: true)
        .appendingPathComponent("LastFMClient.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("LastFMSecrets.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("ListenBrainz", isDirectory: true)
        .appendingPathComponent("ListenBrainzClient.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("ListenBrainz", isDirectory: true)
        .appendingPathComponent("ListenBrainzAuthManager.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("ListenBrainz", isDirectory: true)
        .appendingPathComponent("ListenBrainzSessionStore.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("Scrobble", isDirectory: true)
        .appendingPathComponent("ScrobbleService.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("Scrobble", isDirectory: true)
        .appendingPathComponent("RelativeScrobbleTimeFormatter.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("Scrobble", isDirectory: true)
        .appendingPathComponent("ScrobbleBacklog.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("Scrobble", isDirectory: true)
        .appendingPathComponent("ScrobbleLogStore.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("Scrobble", isDirectory: true)
        .appendingPathComponent("ManualScrobbleError.swift"),
    projectDirectory
        .appendingPathComponent("FastScrobbler", isDirectory: true)
        .appendingPathComponent("Scrobble", isDirectory: true)
        .appendingPathComponent("ScrobbleSkipReason.swift")
]

let temporaryDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("fastscrobbler-run-tests-\(UUID().uuidString)", isDirectory: true)
try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: temporaryDirectory) }

let executable = temporaryDirectory.appendingPathComponent("run_tests")

func run(_ executablePath: String, _ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

let compileStatus = try run(
    "/usr/bin/env",
    ["swiftc"] + sharedSources.map(\.path) + allSources.map(\.path) + ["-o", executable.path]
)
if compileStatus != 0 {
    exit(compileStatus)
}

let passthroughArgs = Array(CommandLine.arguments.dropFirst())
let testStatus = try run(executable.path, passthroughArgs)
if testStatus != 0 {
    exit(testStatus)
}

