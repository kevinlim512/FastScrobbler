#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "xcodeproj"

PROJECT_NAME = "FastScrobbler"
PROJECT_PATH = "#{PROJECT_NAME}.xcodeproj"
IOS_DEPLOYMENT_TARGET = "17.6"
LIVE_ACTIVITY_DEPLOYMENT_TARGET = "16.1"
CONTROL_WIDGET_DEPLOYMENT_TARGET = "18.0"
MACOS_DEPLOYMENT_TARGET = "14.6"

SWIFT_VERSION = "5.0"
DEVELOPMENT_TEAM = "6SVRCQ9AH5"
PROJECT_OBJECT_VERSION = 54
PROJECT_COMPATIBILITY_VERSION = "Xcode 3.2"
PROJECT_LAST_SWIFT_UPDATE_CHECK = "1600"
PROJECT_LAST_UPGRADE_CHECK = "2640"
SCHEME_LAST_UPGRADE_VERSION = "2640"
IOS_APP_MARKETING_VERSION = "6.2"
IOS_APP_CURRENT_PROJECT_VERSION = "6208"
MAC_APP_MARKETING_VERSION = "6.2"
MAC_APP_CURRENT_PROJECT_VERSION = "6208"
EXTENSION_MARKETING_VERSION = "1.0"
EXTENSION_CURRENT_PROJECT_VERSION = "1"

MAIN_APP_BUNDLE_ID = "com.kevin.FastScrobbler"
LIVE_ACTIVITY_BUNDLE_ID = "com.kevin.FastScrobbler.liveactivity"
NOW_PLAYING_CONTROL_BUNDLE_ID = "com.kevin.FastScrobbler.nowplayingcontrol"
SCROBBLE_CONTROL_BUNDLE_ID = "com.kevin.FastScrobbler.scrobblecontrol"
MANUAL_SCROBBLE_CONTROL_BUNDLE_ID = "com.kevin.FastScrobbler.manualscrobblecontrol"
LISTENING_HISTORY_CONTROL_BUNDLE_ID = "com.kevin.FastScrobbler.listeninghistorycontrol"
MAC_APP_BUNDLE_ID = "com.kevin.FastScrobbler"

FIREBASE_PACKAGE_REPOSITORY_URL = "https://github.com/firebase/firebase-ios-sdk.git"
FIREBASE_PACKAGE_REQUIREMENT = {
  "kind" => "upToNextMajorVersion",
  "minimumVersion" => "12.13.0",
}.freeze
CRASHLYTICS_PACKAGE_PRODUCT = "FirebaseCrashlytics"
CRASHLYTICS_SCRIPT_INPUT_PATHS = [
  "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}",
  "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}",
  "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}.debug.dylib",
  "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Info.plist",
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist",
  "$(SRCROOT)/GoogleService-Info.plist",
  "$(SRCROOT)/FastScrobbler/GoogleService-Info.plist",
  "$(SRCROOT)/FastScrobbler/Resources/GoogleService-Info.plist",
  "$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)",
].freeze
IOS_CRASHLYTICS_SCRIPT_INPUT_PATHS = [
  "${DWARF_DSYM_FOLDER_PATH}",
  *CRASHLYTICS_SCRIPT_INPUT_PATHS,
].freeze
CRASHLYTICS_SCRIPT = <<~SCRIPT.chomp
  if [ -z "${DWARF_DSYM_FILE_NAME}" ] || [ ! -d "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}" ]; then
    echo "Skipping Crashlytics symbol upload: dSYM not found for ${CONFIGURATION}."
    exit 0
  fi

  gsp_path=""
  if [ -f "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist" ]; then
    gsp_path="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
  elif [ -f "${SRCROOT}/GoogleService-Info.plist" ]; then
    gsp_path="${SRCROOT}/GoogleService-Info.plist"
  elif [ -f "${SRCROOT}/FastScrobbler/Resources/GoogleService-Info.plist" ]; then
    gsp_path="${SRCROOT}/FastScrobbler/Resources/GoogleService-Info.plist"
  elif [ -f "${SRCROOT}/FastScrobbler/GoogleService-Info.plist" ]; then
    gsp_path="${SRCROOT}/FastScrobbler/GoogleService-Info.plist"
  fi

  if [ -z "${gsp_path}" ]; then
    echo "Skipping Crashlytics symbol upload: GoogleService-Info.plist not found."
    exit 0
  fi

  if ! grep -q "<key>GOOGLE_APP_ID</key>" "${gsp_path}" || grep -q "YOUR_GOOGLE_APP_ID" "${gsp_path}"; then
    echo "Skipping Crashlytics symbol upload: GOOGLE_APP_ID not configured in GoogleService-Info.plist."
    exit 0
  fi

  crashlytics_dir="${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics"
  if [ -f "${crashlytics_dir}/run" ]; then
    "${crashlytics_dir}/run" -gsp "${gsp_path}"
  else
    echo "Skipping Crashlytics symbol upload: run script not found."
  fi
SCRIPT
IOS_CRASHLYTICS_SCRIPT = <<~SCRIPT.chomp
  if [ -z "${DWARF_DSYM_FILE_NAME}" ] || [ ! -d "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}" ]; then
    echo "Skipping Crashlytics symbol upload: dSYM not found for ${CONFIGURATION}."
    exit 0
  fi

  gsp_path=""
  if [ -f "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist" ]; then
    gsp_path="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
  elif [ -f "${SRCROOT}/GoogleService-Info.plist" ]; then
    gsp_path="${SRCROOT}/GoogleService-Info.plist"
  elif [ -f "${SRCROOT}/FastScrobbler/Resources/GoogleService-Info.plist" ]; then
    gsp_path="${SRCROOT}/FastScrobbler/Resources/GoogleService-Info.plist"
  elif [ -f "${SRCROOT}/FastScrobbler/GoogleService-Info.plist" ]; then
    gsp_path="${SRCROOT}/FastScrobbler/GoogleService-Info.plist"
  fi

  if [ -z "${gsp_path}" ]; then
    echo "Skipping Crashlytics symbol upload: GoogleService-Info.plist not found."
    exit 0
  fi

  if ! grep -q "<key>GOOGLE_APP_ID</key>" "${gsp_path}" || grep -q "YOUR_GOOGLE_APP_ID" "${gsp_path}"; then
    echo "Skipping Crashlytics symbol upload: GOOGLE_APP_ID not configured in GoogleService-Info.plist."
    exit 0
  fi

  crashlytics_dir="${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics"
  if [ "${PLATFORM_NAME}" = "iphoneos" ]; then
    if [ -f "${crashlytics_dir}/upload-symbols" ]; then
      "${crashlytics_dir}/upload-symbols" \
        -gsp "${gsp_path}" \
        -p ios \
        -- "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}"
    else
      echo "Skipping Crashlytics symbol upload: upload-symbols binary not found."
    fi
  else
    if [ -f "${crashlytics_dir}/run" ]; then
      "${crashlytics_dir}/run" -gsp "${gsp_path}"
    else
      echo "Skipping Crashlytics symbol upload: run script not found."
    fi
  fi
SCRIPT

IGNORED_DIRS = %w[DerivedData build].freeze
IGNORED_FILES = [".DS_Store"].freeze
IGNORED_SUFFIXES = ["_Template.swift", "_template.swift"].freeze
KNOWN_REGIONS = %w[en Base es fr ja zh-Hans].freeze

PROJECT_BUILD_SETTINGS = {
  "Debug" => {
    "ALWAYS_SEARCH_USER_PATHS" => "NO",
    "CLANG_ANALYZER_LOCALIZABILITY_NONLOCALIZED" => "YES",
    "CLANG_ANALYZER_NONNULL" => "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION" => "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD" => "gnu++14",
    "CLANG_CXX_LIBRARY" => "libc++",
    "CLANG_ENABLE_MODULES" => "YES",
    "CLANG_ENABLE_OBJC_ARC" => "YES",
    "CLANG_ENABLE_OBJC_WEAK" => "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING" => "YES",
    "CLANG_WARN_BOOL_CONVERSION" => "YES",
    "CLANG_WARN_COMMA" => "YES",
    "CLANG_WARN_CONSTANT_CONVERSION" => "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS" => "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE" => "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS" => "YES",
    "CLANG_WARN_EMPTY_BODY" => "YES",
    "CLANG_WARN_ENUM_CONVERSION" => "YES",
    "CLANG_WARN_INFINITE_RECURSION" => "YES",
    "CLANG_WARN_INT_CONVERSION" => "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION" => "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF" => "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION" => "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS" => "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER" => "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS" => "YES",
    "CLANG_WARN_STRICT_PROTOTYPES" => "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE" => "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY" => "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE" => "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH" => "YES",
    "COPY_PHASE_STRIP" => "NO",
    "DEAD_CODE_STRIPPING" => "YES",
    "DEBUG_INFORMATION_FORMAT" => "dwarf-with-dsym",
    "ENABLE_DEBUG_DYLIB" => "NO",
    "ENABLE_STRICT_OBJC_MSGSEND" => "YES",
    "ENABLE_TESTABILITY" => "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING" => "YES",
    "GCC_C_LANGUAGE_STANDARD" => "gnu11",
    "GCC_DYNAMIC_NO_PIC" => "NO",
    "GCC_NO_COMMON_BLOCKS" => "YES",
    "GCC_OPTIMIZATION_LEVEL" => "0",
    "GCC_PREPROCESSOR_DEFINITIONS" => ["DEBUG=1", "$(inherited)"],
    "GCC_WARN_64_TO_32_BIT_CONVERSION" => "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE" => "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR" => "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS" => "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION" => "YES",
    "GCC_WARN_UNUSED_VARIABLE" => "YES",
    "MTL_ENABLE_DEBUG_INFO" => "INCLUDE_SOURCE",
    "MTL_FAST_MATH" => "YES",
    "ONLY_ACTIVE_ARCH" => "YES",
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "STRING_CATALOG_GENERATE_SYMBOLS" => "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS" => "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL" => "-Onone",
    "SWIFT_VERSION" => SWIFT_VERSION,
  },
  "Release" => {
    "ALWAYS_SEARCH_USER_PATHS" => "NO",
    "CLANG_ANALYZER_LOCALIZABILITY_NONLOCALIZED" => "YES",
    "CLANG_ANALYZER_NONNULL" => "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION" => "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD" => "gnu++14",
    "CLANG_CXX_LIBRARY" => "libc++",
    "CLANG_ENABLE_MODULES" => "YES",
    "CLANG_ENABLE_OBJC_ARC" => "YES",
    "CLANG_ENABLE_OBJC_WEAK" => "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING" => "YES",
    "CLANG_WARN_BOOL_CONVERSION" => "YES",
    "CLANG_WARN_COMMA" => "YES",
    "CLANG_WARN_CONSTANT_CONVERSION" => "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS" => "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE" => "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS" => "YES",
    "CLANG_WARN_EMPTY_BODY" => "YES",
    "CLANG_WARN_ENUM_CONVERSION" => "YES",
    "CLANG_WARN_INFINITE_RECURSION" => "YES",
    "CLANG_WARN_INT_CONVERSION" => "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION" => "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF" => "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION" => "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS" => "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER" => "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS" => "YES",
    "CLANG_WARN_STRICT_PROTOTYPES" => "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE" => "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY" => "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE" => "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH" => "YES",
    "COPY_PHASE_STRIP" => "NO",
    "DEAD_CODE_STRIPPING" => "YES",
    "DEBUG_INFORMATION_FORMAT" => "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS" => "NO",
    "ENABLE_STRICT_OBJC_MSGSEND" => "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING" => "YES",
    "GCC_C_LANGUAGE_STANDARD" => "gnu11",
    "GCC_NO_COMMON_BLOCKS" => "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION" => "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE" => "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR" => "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS" => "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION" => "YES",
    "GCC_WARN_UNUSED_VARIABLE" => "YES",
    "MTL_ENABLE_DEBUG_INFO" => "NO",
    "MTL_FAST_MATH" => "YES",
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "STRING_CATALOG_GENERATE_SYMBOLS" => "YES",
    "SWIFT_COMPILATION_MODE" => "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL" => "-O",
    "SWIFT_VERSION" => SWIFT_VERSION,
  },
}.freeze

def localized_resources(root_path)
  Dir.glob("#{root_path}/*.lproj").sort
end

SHARED_CORE_SOURCES = %w[
  FastScrobbler/AppModel.swift
  FastScrobbler/ContentView.swift
  FastScrobbler/LastFM/LastFMAuthManager.swift
  FastScrobbler/LastFM/LastFMClient.swift
  FastScrobbler/LastFM/LastFMSessionStore.swift
  FastScrobbler/ListenBrainz/ListenBrainzAuthManager.swift
  FastScrobbler/ListenBrainz/ListenBrainzClient.swift
  FastScrobbler/ListenBrainz/ListenBrainzConnectSheet.swift
  FastScrobbler/ListenBrainz/ListenBrainzSessionStore.swift
  FastScrobbler/LastFMSecrets.swift
  FastScrobbler/Models/Track.swift
  FastScrobbler/ProPurchaseManager.swift
  FastScrobbler/Scrobble/LivePlaybackSnapshot.swift
  FastScrobbler/Scrobble/ScrobbleBacklog.swift
  FastScrobbler/Scrobble/ScrobbleEngine.swift
  FastScrobbler/Scrobble/ManualScrobbleError.swift
  FastScrobbler/Scrobble/ScrobbleService.swift
  FastScrobbler/Scrobble/ScrobbleSkipReason.swift
  FastScrobbler/Scrobble/ScrobbleLogStore.swift
  FastScrobbler/Scrobble/RelativeScrobbleTimeFormatter.swift
  FastScrobbler/SettingsView.swift
  FastScrobbler/WhatsNewRelease.swift
  FastScrobbler/ICloudSyncCoordinator.swift
].freeze

IOS_APP_SOURCES = (SHARED_CORE_SOURCES + %w[
  FastScrobbler/AppDelegate.swift
  FastScrobbler/AppleMusicAPISettingsPage.swift
  FastScrobbler/BackgroundTaskManager.swift
  FastScrobbler/Intents/ControlWidgetStatus.swift
  FastScrobbler/Intents/ScrobbleShortcutsIntents.swift
  FastScrobbler/FullscreenNowPlayingView.swift
  FastScrobbler/LiveActivity/LiveActivityManager.swift
  FastScrobbler/LiveActivity/ScrobblingActivityAttributes.swift
  FastScrobbler/ManualScrobbleView.swift
  FastScrobbler/NowPlaying/AppleMusicFavorites.swift
  FastScrobbler/NowPlaying/AppleMusicNowPlayingObserver.swift
  FastScrobbler/NowPlaying/AppleMusicRecentTracksImporter.swift
  FastScrobbler/NowPlaying/ListeningHistoryScanService.swift
  FastScrobbler/NowPlaying/PlaybackHistoryImporter.swift
  FastScrobbler/Pro.swift
  FastScrobbler/RemoveBracketsSettingsPage.swift
  FastScrobbler/SceneDelegate.swift
  FastScrobbler/SetupHelpView.swift
  FastScrobbler/TextReplacementSettingsPage.swift
  FastScrobbler/WhatsNewView.swift
]).freeze

MAC_APP_SOURCES = %w[
  FastScrobbler/LastFM/LastFMAuthManager.swift
  FastScrobbler/LastFM/LastFMClient.swift
  FastScrobbler/LastFM/LastFMSessionStore.swift
  FastScrobbler/ListenBrainz/ListenBrainzAuthManager.swift
  FastScrobbler/ListenBrainz/ListenBrainzClient.swift
  FastScrobbler/ListenBrainz/ListenBrainzConnectSheet.swift
  FastScrobbler/ListenBrainz/ListenBrainzSessionStore.swift
  FastScrobbler/LastFMSecrets.swift
  FastScrobbler/Models/Track.swift
  FastScrobbler/ProPurchaseManager.swift
  FastScrobbler/RemoveBracketsSettingsPage.swift
  FastScrobbler/Scrobble/LivePlaybackSnapshot.swift
  FastScrobbler/Scrobble/ScrobbleBacklog.swift
  FastScrobbler/Scrobble/ScrobbleEngine.swift
  FastScrobbler/Scrobble/ManualScrobbleError.swift
  FastScrobbler/Scrobble/ScrobbleService.swift
  FastScrobbler/Scrobble/ScrobbleSkipReason.swift
  FastScrobbler/Scrobble/ScrobbleLogStore.swift
  FastScrobbler/Scrobble/RelativeScrobbleTimeFormatter.swift
  FastScrobbler/TextReplacementSettingsPage.swift
  FastScrobbler/WhatsNewRelease.swift
  FastScrobblerMac/AppModel.swift
  FastScrobblerMac/AppleMusicNowPlayingObserver.swift
  FastScrobblerMac/BackgroundTaskManager.swift
  FastScrobblerMac/ContentView.swift
  FastScrobblerMac/FastScrobblerMacApp.swift
  FastScrobblerMac/LiveActivityManager.swift
  FastScrobblerMac/ManualScrobbleView.swift
  FastScrobblerMac/MenuBarController.swift
  FastScrobblerMac/MediaPlayerShims.swift
  FastScrobblerMac/PlaybackHistoryImporter.swift
  FastScrobblerMac/SettingsView.swift
  FastScrobblerMac/SetupHelpView.swift
  FastScrobblerMac/ListenBrainzConnectView.swift
].freeze

LIVE_ACTIVITY_SOURCES = %w[
  FastScrobbler/LiveActivity/ScrobblingActivityAttributes.swift
  FastScrobblerLiveActivity/FastScrobblerLiveActivityBundle.swift
  FastScrobblerLiveActivity/ScrobblingLiveActivityWidget.swift
].freeze

CONTROL_SHARED_SOURCES = %w[
  FastScrobbler/Intents/ControlWidgetStatus.swift
  FastScrobbler/Intents/ScrobbleShortcutsIntents.swift
  FastScrobbler/LastFM/LastFMClient.swift
  FastScrobbler/LastFM/LastFMSessionStore.swift
  FastScrobbler/ListenBrainz/ListenBrainzClient.swift
  FastScrobbler/ListenBrainz/ListenBrainzSessionStore.swift
  FastScrobbler/LastFMSecrets.swift
  FastScrobbler/Models/Track.swift
  FastScrobbler/NowPlaying/AppleMusicFavorites.swift
  FastScrobbler/NowPlaying/AppleMusicRecentTracksImporter.swift
  FastScrobbler/NowPlaying/ListeningHistoryScanService.swift
  FastScrobbler/NowPlaying/PlaybackHistoryImporter.swift
  FastScrobbler/Scrobble/ScrobbleBacklog.swift
  FastScrobbler/Scrobble/ScrobbleService.swift
  FastScrobbler/Scrobble/ScrobbleLogStore.swift
].freeze

NOW_PLAYING_CONTROL_SOURCES = (CONTROL_SHARED_SOURCES + %w[
  FastScrobblerNowPlayingControl/SendNowPlayingControlWidget.swift
]).freeze

SCROBBLE_CONTROL_SOURCES = (CONTROL_SHARED_SOURCES + %w[
  FastScrobblerScrobbleControl/ScrobbleSongControlWidget.swift
]).freeze

MANUAL_SCROBBLE_CONTROL_SOURCES = (CONTROL_SHARED_SOURCES + %w[
  FastScrobblerManualScrobbleControl/ManualScrobbleControlWidget.swift
]).freeze

LISTENING_HISTORY_CONTROL_SOURCES = (CONTROL_SHARED_SOURCES + %w[
  FastScrobblerListeningHistoryControl/ScanListeningHistoryControlWidget.swift
]).freeze

IOS_APP_RESOURCES = (
  %w[
    AppIcon.icon
    FastScrobbler/Resources/Assets.xcassets
    FastScrobbler/Resources/LaunchScreen.storyboard
  ] + (File.exist?("GoogleService-Info.plist") ? ["GoogleService-Info.plist"] : []) + localized_resources("FastScrobbler")
).freeze

MAC_APP_RESOURCES = (
  %w[
    AppIcon.icon
    FastScrobbler/Resources/Assets.xcassets
  ] + (File.exist?("GoogleService-Info.plist") ? ["GoogleService-Info.plist"] : []) + localized_resources("FastScrobblerMac")
).freeze

ROOT_FILE_PATHS = (
  %w[AppIcon.icon] + (File.exist?("GoogleService-Info.plist") ? ["GoogleService-Info.plist"] : [])
).freeze

ROOT_GROUP_PATHS = %w[
  FastScrobbler
  FastScrobblerMac
  FastScrobblerLiveActivity
  FastScrobblerNowPlayingControl
  FastScrobblerScrobbleControl
  FastScrobblerManualScrobbleControl
  FastScrobblerListeningHistoryControl
  FastScrobbler.storekit
].freeze

TARGET_DEFINITIONS = [
  {
    name: "FastScrobbler",
    type: :application,
    platform: :ios,
    deployment_target: IOS_DEPLOYMENT_TARGET,
    bundle_id: MAIN_APP_BUNDLE_ID,
    info_plist: "FastScrobbler/Info.plist",
    entitlements: "FastScrobbler/FastScrobbler.entitlements",
    sources: IOS_APP_SOURCES,
    resources: IOS_APP_RESOURCES,
    app_icon: "AppIcon",
    accent_color: "AccentColor",
    include_all_app_icon_assets: "YES",
    supported_platforms: "iphoneos iphonesimulator",
    targeted_device_family: "1",
    skip_install: "NO",
    application_extension_api_only: "NO",
    development_team: DEVELOPMENT_TEAM,
    marketing_version: IOS_APP_MARKETING_VERSION,
    current_project_version: IOS_APP_CURRENT_PROJECT_VERSION,
    sdkroot: "iphoneos",
    ld_runpath_search_paths: ["$(inherited)", "@executable_path/Frameworks"],
    clang_enable_objc_weak: "NO",
    package_products: [CRASHLYTICS_PACKAGE_PRODUCT],
    build_settings_overrides: {
      "Debug" => {
        "DEBUG_INFORMATION_FORMAT" => "dwarf-with-dsym",
      },
    },
    shell_script_build_phases: [
      {
        name: "Firebase Crashlytics",
        always_out_of_date: "1",
        input_paths: IOS_CRASHLYTICS_SCRIPT_INPUT_PATHS,
        show_env_vars_in_log: "0",
        shell_script: IOS_CRASHLYTICS_SCRIPT,
      },
    ],
    frameworks: %w[
      ActivityKit
      AppIntents
      AuthenticationServices
      BackgroundTasks
      MediaPlayer
      MusicKit
      SafariServices
      StoreKit
      WidgetKit
    ],
  },
  {
    name: "FastScrobblerMac",
    product_name: "FastScrobbler",
    product_module_name: "FastScrobbler",
    type: :application,
    platform: :osx,
    deployment_target: MACOS_DEPLOYMENT_TARGET,
    bundle_id: MAC_APP_BUNDLE_ID,
    info_plist: "FastScrobblerMac/Info.plist",
    entitlements: "FastScrobblerMac/FastScrobblerMac.entitlements",
    sources: MAC_APP_SOURCES,
    resources: MAC_APP_RESOURCES,
    app_icon: "AppIcon",
    accent_color: "AccentColor",
    include_all_app_icon_assets: "YES",
    supported_platforms: "macosx",
    skip_install: "NO",
    application_extension_api_only: "NO",
    development_team: DEVELOPMENT_TEAM,
    marketing_version: MAC_APP_MARKETING_VERSION,
    current_project_version: MAC_APP_CURRENT_PROJECT_VERSION,
    sdkroot: "macosx",
    ld_runpath_search_paths: ["$(inherited)", "@executable_path/../Frameworks"],
    combine_hidpi_images: "YES",
    dead_code_stripping: "YES",
    register_app_groups: "YES",
    package_products: [CRASHLYTICS_PACKAGE_PRODUCT],
    build_settings_overrides: {
      "Debug" => {
        "DEBUG_INFORMATION_FORMAT" => "dwarf-with-dsym",
      },
    },
    shell_script_build_phases: [
      {
        name: "Firebase Crashlytics",
        always_out_of_date: "1",
        input_paths: CRASHLYTICS_SCRIPT_INPUT_PATHS,
        show_env_vars_in_log: "0",
        shell_script: CRASHLYTICS_SCRIPT,
      },
    ],
    frameworks: %w[
      AppKit
      AuthenticationServices
      MediaPlayer
      MusicKit
      ServiceManagement
      StoreKit
    ],
  },
  {
    name: "FastScrobblerLiveActivity",
    type: :app_extension,
    platform: :ios,
    deployment_target: LIVE_ACTIVITY_DEPLOYMENT_TARGET,
    bundle_id: LIVE_ACTIVITY_BUNDLE_ID,
    info_plist: "FastScrobblerLiveActivity/Info.plist",
    entitlements: "FastScrobblerLiveActivity/FastScrobblerLiveActivity.entitlements",
    sources: LIVE_ACTIVITY_SOURCES,
    resources: [],
    supported_platforms: "iphoneos iphonesimulator",
    targeted_device_family: "1",
    skip_install: "YES",
    application_extension_api_only: "YES",
    development_team: DEVELOPMENT_TEAM,
    marketing_version: EXTENSION_MARKETING_VERSION,
    current_project_version: EXTENSION_CURRENT_PROJECT_VERSION,
    sdkroot: "iphoneos",
    validate_product: "YES",
    clang_enable_objc_weak: "NO",
    frameworks: %w[
      ActivityKit
      SwiftUI
      WidgetKit
    ],
  },
  {
    name: "FastScrobblerNowPlayingControl",
    type: :app_extension,
    platform: :ios,
    deployment_target: CONTROL_WIDGET_DEPLOYMENT_TARGET,
    bundle_id: NOW_PLAYING_CONTROL_BUNDLE_ID,
    info_plist: "FastScrobblerNowPlayingControl/Info.plist",
    entitlements: "FastScrobblerNowPlayingControl/FastScrobblerNowPlayingControl.entitlements",
    sources: NOW_PLAYING_CONTROL_SOURCES,
    resources: localized_resources("FastScrobblerNowPlayingControl"),
    supported_platforms: "iphoneos iphonesimulator",
    targeted_device_family: "1",
    skip_install: "YES",
    application_extension_api_only: "YES",
    development_team: DEVELOPMENT_TEAM,
    marketing_version: EXTENSION_MARKETING_VERSION,
    current_project_version: EXTENSION_CURRENT_PROJECT_VERSION,
    sdkroot: "iphoneos",
    validate_product: "YES",
    clang_enable_objc_weak: "NO",
    frameworks: %w[
      AppIntents
      MediaPlayer
      MusicKit
      WidgetKit
    ],
  },
  {
    name: "FastScrobblerScrobbleControl",
    type: :app_extension,
    platform: :ios,
    deployment_target: CONTROL_WIDGET_DEPLOYMENT_TARGET,
    bundle_id: SCROBBLE_CONTROL_BUNDLE_ID,
    info_plist: "FastScrobblerScrobbleControl/Info.plist",
    entitlements: "FastScrobblerScrobbleControl/FastScrobblerScrobbleControl.entitlements",
    sources: SCROBBLE_CONTROL_SOURCES,
    resources: localized_resources("FastScrobblerScrobbleControl"),
    supported_platforms: "iphoneos iphonesimulator",
    targeted_device_family: "1",
    skip_install: "YES",
    application_extension_api_only: "YES",
    development_team: DEVELOPMENT_TEAM,
    marketing_version: EXTENSION_MARKETING_VERSION,
    current_project_version: EXTENSION_CURRENT_PROJECT_VERSION,
    sdkroot: "iphoneos",
    validate_product: "YES",
    clang_enable_objc_weak: "NO",
    frameworks: %w[
      AppIntents
      MediaPlayer
      MusicKit
      WidgetKit
    ],
  },
  {
    name: "FastScrobblerManualScrobbleControl",
    type: :app_extension,
    platform: :ios,
    deployment_target: CONTROL_WIDGET_DEPLOYMENT_TARGET,
    bundle_id: MANUAL_SCROBBLE_CONTROL_BUNDLE_ID,
    info_plist: "FastScrobblerManualScrobbleControl/Info.plist",
    entitlements: "FastScrobblerManualScrobbleControl/FastScrobblerManualScrobbleControl.entitlements",
    sources: MANUAL_SCROBBLE_CONTROL_SOURCES,
    resources: [],
    supported_platforms: "iphoneos iphonesimulator",
    targeted_device_family: "1",
    skip_install: "YES",
    application_extension_api_only: "YES",
    development_team: DEVELOPMENT_TEAM,
    marketing_version: EXTENSION_MARKETING_VERSION,
    current_project_version: EXTENSION_CURRENT_PROJECT_VERSION,
    sdkroot: "iphoneos",
    validate_product: "YES",
    clang_enable_objc_weak: "NO",
    frameworks: %w[
      AppIntents
      MediaPlayer
      MusicKit
      WidgetKit
    ],
  },
  {
    name: "FastScrobblerListeningHistoryControl",
    type: :app_extension,
    platform: :ios,
    deployment_target: CONTROL_WIDGET_DEPLOYMENT_TARGET,
    bundle_id: LISTENING_HISTORY_CONTROL_BUNDLE_ID,
    info_plist: "FastScrobblerListeningHistoryControl/Info.plist",
    entitlements: "FastScrobblerListeningHistoryControl/FastScrobblerListeningHistoryControl.entitlements",
    sources: LISTENING_HISTORY_CONTROL_SOURCES,
    resources: localized_resources("FastScrobblerListeningHistoryControl"),
    supported_platforms: "iphoneos iphonesimulator",
    targeted_device_family: "1",
    skip_install: "YES",
    application_extension_api_only: "YES",
    development_team: DEVELOPMENT_TEAM,
    marketing_version: EXTENSION_MARKETING_VERSION,
    current_project_version: EXTENSION_CURRENT_PROJECT_VERSION,
    sdkroot: "iphoneos",
    validate_product: "YES",
    clang_enable_objc_weak: "NO",
    frameworks: %w[
      AppIntents
      MediaPlayer
      MusicKit
      WidgetKit
    ],
  },
].freeze

def ignored_entry?(name, full_path)
  return true if name.start_with?(".")
  return true if IGNORED_FILES.include?(name)
  return true if IGNORED_SUFFIXES.any? { |suffix| name.end_with?(suffix) }
  return true if File.directory?(full_path) && IGNORED_DIRS.include?(name)

  false
end

def add_tree(group, relative_dir, refs_by_path)
  Dir.children(relative_dir).sort.each do |child|
    full_path = File.join(relative_dir, child)
    next if ignored_entry?(child, full_path)

    if File.directory?(full_path) && !File.extname(child).empty?
      ref = group.new_file(child)
      refs_by_path[full_path] = ref
    elsif File.directory?(full_path)
      subgroup = group.new_group(child, child)
      add_tree(subgroup, full_path, refs_by_path)
    else
      ref = group.new_file(child)
      refs_by_path[full_path] = ref
    end
  end
end

def source_refs(paths, refs_by_path)
  paths.map do |path|
    ref = refs_by_path[path]
    raise "Missing file reference for #{path}" unless ref

    ref
  end
end

def apply_common_build_settings(target, definition)
  target.build_configurations.each do |config|
    settings = config.build_settings
    settings.merge!(PROJECT_BUILD_SETTINGS.fetch(config.name))
    settings.merge!(definition.dig(:build_settings_overrides, config.name) || {})
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = definition[:bundle_id]
    settings["PRODUCT_NAME"] = definition.fetch(:product_name, definition[:name])
    settings["PRODUCT_MODULE_NAME"] = definition[:product_module_name] if definition[:product_module_name]
    settings["INFOPLIST_FILE"] = definition[:info_plist]
    settings["GENERATE_INFOPLIST_FILE"] = "NO"
    settings["SWIFT_VERSION"] = SWIFT_VERSION
    settings["MARKETING_VERSION"] = definition[:marketing_version]
    settings["CURRENT_PROJECT_VERSION"] = definition[:current_project_version]
    settings["CODE_SIGN_STYLE"] = "Automatic"
    settings["CODE_SIGN_ENTITLEMENTS"] = definition[:entitlements] if definition[:entitlements]
    settings["DEVELOPMENT_TEAM"] = definition[:development_team] if definition[:development_team]
    settings["SDKROOT"] = definition[:sdkroot] if definition[:sdkroot]
    settings["LD_RUNPATH_SEARCH_PATHS"] = definition[:ld_runpath_search_paths] if definition[:ld_runpath_search_paths]
    settings["SUPPORTED_PLATFORMS"] = definition[:supported_platforms] if definition[:supported_platforms]
    settings["TARGETED_DEVICE_FAMILY"] = definition[:targeted_device_family] if definition[:targeted_device_family]
    settings["APPLICATION_EXTENSION_API_ONLY"] = definition[:application_extension_api_only]
    settings["SKIP_INSTALL"] = definition[:skip_install]
    if definition[:validate_product] && config.name == "Release"
      settings["VALIDATE_PRODUCT"] = definition[:validate_product]
    end
    settings["CLANG_ENABLE_OBJC_WEAK"] = definition[:clang_enable_objc_weak] if definition[:clang_enable_objc_weak]
    settings["COMBINE_HIDPI_IMAGES"] = definition[:combine_hidpi_images] if definition[:combine_hidpi_images]
    settings["DEAD_CODE_STRIPPING"] = definition[:dead_code_stripping] if definition[:dead_code_stripping]
    settings["REGISTER_APP_GROUPS"] = definition[:register_app_groups] if definition[:register_app_groups]
    settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = definition[:app_icon] if definition[:app_icon]
    settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = definition[:accent_color] if definition[:accent_color]
    settings["ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS"] = definition[:include_all_app_icon_assets] if definition[:include_all_app_icon_assets]
  end
end

def ensure_remote_package(project, repository_url, requirement)
  existing_package = project.root_object.package_references.find do |package|
    package.isa == "XCRemoteSwiftPackageReference" && package.repositoryURL == repository_url
  end
  return existing_package if existing_package

  project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference).tap do |package|
    package.repositoryURL = repository_url
    package.requirement = requirement
    project.root_object.package_references << package
  end
end

def add_package_product_dependency(target, package, product_name)
  product_dependency = target.project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product_dependency.package = package
  product_dependency.product_name = product_name
  target.package_product_dependencies << product_dependency

  build_file = target.project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product_dependency
  target.frameworks_build_phase.files << build_file
end

def add_shell_script_build_phase(target, definition)
  phase = target.new_shell_script_build_phase(definition[:name])
  phase.always_out_of_date = definition[:always_out_of_date] if definition[:always_out_of_date]
  phase.input_paths = definition[:input_paths] if definition[:input_paths]
  phase.input_file_list_paths = definition[:input_file_list_paths] if definition[:input_file_list_paths]
  phase.output_paths = definition[:output_paths] if definition[:output_paths]
  phase.output_file_list_paths = definition[:output_file_list_paths] if definition[:output_file_list_paths]
  phase.shell_path = definition[:shell_path] if definition[:shell_path]
  phase.shell_script = definition[:shell_script] if definition[:shell_script]
  phase.show_env_vars_in_log = definition[:show_env_vars_in_log] if definition[:show_env_vars_in_log]
  phase.run_only_for_deployment_postprocessing = definition[:run_only_for_deployment_postprocessing] if definition[:run_only_for_deployment_postprocessing]
end

def apply_project_settings(project)
  project.root_object.compatibility_version = PROJECT_COMPATIBILITY_VERSION
  project.root_object.attributes["BuildIndependentTargetsInParallel"] = "YES"
  project.root_object.attributes["LastSwiftUpdateCheck"] = PROJECT_LAST_SWIFT_UPDATE_CHECK
  project.root_object.attributes["LastUpgradeCheck"] = PROJECT_LAST_UPGRADE_CHECK

  project.build_configurations.each do |config|
    config.build_settings.merge!(PROJECT_BUILD_SETTINGS.fetch(config.name))
  end
end

def add_storekit_configuration(scheme)
  element = scheme.launch_action.xml_element.add_element("StoreKitConfigurationFileReference")
  element.add_attribute("identifier", "../../FastScrobbler.storekit/Configuration.storekit")
end

def create_shared_scheme(project_path, target)
  scheme = Xcodeproj::XCScheme.new
  scheme.configure_with_targets(target, nil, launch_target: target.product_type == "com.apple.product-type.application")
  scheme.doc.elements["Scheme"].attributes["LastUpgradeVersion"] = SCHEME_LAST_UPGRADE_VERSION
  add_storekit_configuration(scheme) if target.name == "FastScrobbler"
  scheme.save_as(project_path, target.name, true)
end

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH, false, PROJECT_OBJECT_VERSION)
project.root_object.known_regions = KNOWN_REGIONS
apply_project_settings(project)

refs_by_path = {}
ROOT_FILE_PATHS.each do |root_path|
  refs_by_path[root_path] = project.main_group.new_file(root_path)
end

ROOT_GROUP_PATHS.each do |root_path|
  group = project.main_group.new_group(File.basename(root_path), root_path)
  add_tree(group, root_path, refs_by_path)
end

targets = {}
firebase_package = ensure_remote_package(project, FIREBASE_PACKAGE_REPOSITORY_URL, FIREBASE_PACKAGE_REQUIREMENT)
TARGET_DEFINITIONS.each do |definition|
  target = project.new_target(
    definition[:type],
    definition[:name],
    definition[:platform],
    definition[:deployment_target]
  )

  apply_common_build_settings(target, definition)
  target.add_file_references(source_refs(definition[:sources], refs_by_path))
  target.add_resources(source_refs(definition[:resources], refs_by_path))
  target.add_system_frameworks(definition[:frameworks])
  Array(definition[:package_products]).each do |product_name|
    add_package_product_dependency(target, firebase_package, product_name)
  end
  targets[definition[:name]] = target
end

ios_app = targets.fetch("FastScrobbler")
embedded_extensions = [
  targets.fetch("FastScrobblerLiveActivity"),
  targets.fetch("FastScrobblerNowPlayingControl"),
  targets.fetch("FastScrobblerScrobbleControl"),
  targets.fetch("FastScrobblerManualScrobbleControl"),
  targets.fetch("FastScrobblerListeningHistoryControl"),
]

embed_phase = ios_app.new_copy_files_build_phase("Embed Foundation Extensions")
embed_phase.symbol_dst_subfolder_spec = :plug_ins

embedded_extensions.each do |extension_target|
  ios_app.add_dependency(extension_target)
  build_file = embed_phase.add_file_reference(extension_target.product_reference, true)
  build_file.settings = { "ATTRIBUTES" => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
end

TARGET_DEFINITIONS.each do |definition|
  target = targets.fetch(definition[:name])
  Array(definition[:shell_script_build_phases]).each do |phase_definition|
    add_shell_script_build_phase(target, phase_definition)
  end
end

project.save

TARGET_DEFINITIONS.each do |definition|
  create_shared_scheme(PROJECT_PATH, targets.fetch(definition[:name]))
end

puts "Wrote #{PROJECT_PATH}"
puts "Targets: #{TARGET_DEFINITIONS.map { |definition| definition[:name] }.join(', ')}"
