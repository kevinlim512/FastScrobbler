// Rename this file from "LastFMSecrets_Template.swift" to "LastFMSecrets.swift"

import Foundation

enum LastFMSecrets {
    // Create an API account at https://www.last.fm/api/account/create
    // Then input the API key and secret here
    static let apiKey = ""
    static let apiSecret = ""

    // Must match `CFBundleURLTypes` in `FastScrobbler/Info.plist`.
    static let callbackScheme = "lastfmscrobble"
    static let callbackPath = "auth"
}
