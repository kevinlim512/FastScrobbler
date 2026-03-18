#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "xcodeproj"

PROJECT_NAME = "FastScrobbler"
PROJECT_PATH = "#{PROJECT_NAME}.xcodeproj"
IOS_DEPLOYMENT_TARGET = "17.0"
LIVE_ACTIVITY_DEPLOYMENT_TARGET = "16.1"
CONTROL_WIDGET_DEPLOYMENT_TARGET = "18.0"
MACOS_DEPLOYMENT_TARGET = "13.5"

SWIFT_VERSION = "5.0"
MARKETING_VERSION = "1.0"
CURRENT_PROJECT_VERSION = "1"

MAIN_APP_BUNDLE_ID = "com.kevin.FastScrobbler"
LIVE_ACTIVITY_BUNDLE_ID = "com.kevin.FastScrobbler.liveactivity"
NOW_PLAYING_CONTROL_BUNDLE_ID = "com.kevin.FastScrobbler.nowplayingcontrol"
SCROBBLE_CONTROL_BUNDLE_ID = "com.kevin.FastScrobbler.scrobblecontrol"
MAC_APP_BUNDLE_ID = "com.kevin.FastScrobbler.mac"

IGNORED_DIRS = %w[DerivedData build].freeze
IGNORED_FILES = [".DS_Store"].freeze
IGNORED_SUFFIXES = ["_Template.swift", "_template.swift"].freeze

SHARED_CORE_SOURCES = %w[
  FastScrobbler/AppModel.swift
  FastScrobbler/ContentView.swift
  FastScrobbler/LastFM/KeychainStore.swift
  FastScrobbler/LastFM/LastFMAuthManager.swift
  FastScrobbler/LastFM/LastFMClient.swift
  FastScrobbler/LastFMSecrets.swift
  FastScrobbler/Models/Track.swift
  FastScrobbler/Pro.swift
  FastScrobbler/Scrobble/ScrobbleBacklog.swift
  FastScrobbler/Scrobble/ScrobbleEngine.swift
  FastScrobbler/Scrobble/ScrobbleLogStore.swift
  FastScrobbler/SettingsView.swift
].freeze

IOS_APP_SOURCES = (SHARED_CORE_SOURCES + %w[
  FastScrobbler/AppDelegate.swift
  FastScrobbler/BackgroundTaskManager.swift
  FastScrobbler/Intents/ScrobbleShortcutsIntents.swift
  FastScrobbler/LiveActivity/LiveActivityManager.swift
  FastScrobbler/LiveActivity/ScrobblingActivityAttributes.swift
  FastScrobbler/NowPlaying/AppleMusicFavorites.swift
  FastScrobbler/NowPlaying/AppleMusicNowPlayingObserver.swift
  FastScrobbler/NowPlaying/PlaybackHistoryImporter.swift
  FastScrobbler/SceneDelegate.swift
  FastScrobbler/SetupHelpView.swift
]).freeze

MAC_APP_SOURCES = (SHARED_CORE_SOURCES + %w[
  FastScrobbler/MenuBarController.swift
  FastScrobblerMac/AppleMusicNowPlayingObserver.swift
  FastScrobblerMac/BackgroundTaskManager.swift
  FastScrobblerMac/FastScrobblerMacApp.swift
  FastScrobblerMac/LiveActivityManager.swift
  FastScrobblerMac/MediaPlayerShims.swift
  FastScrobblerMac/PlaybackHistoryImporter.swift
  FastScrobblerMac/SetupHelpView.swift
]).freeze

LIVE_ACTIVITY_SOURCES = %w[
  FastScrobbler/LiveActivity/ScrobblingActivityAttributes.swift
  FastScrobblerLiveActivity/FastScrobblerLiveActivityBundle.swift
  FastScrobblerLiveActivity/ScrobblingLiveActivityWidget.swift
].freeze

CONTROL_SHARED_SOURCES = %w[
  FastScrobbler/Intents/ScrobbleShortcutsIntents.swift
  FastScrobbler/LastFM/KeychainStore.swift
  FastScrobbler/LastFM/LastFMClient.swift
  FastScrobbler/LastFMSecrets.swift
  FastScrobbler/Models/Track.swift
  FastScrobbler/Scrobble/ScrobbleBacklog.swift
  FastScrobbler/Scrobble/ScrobbleLogStore.swift
].freeze

NOW_PLAYING_CONTROL_SOURCES = (CONTROL_SHARED_SOURCES + %w[
  FastScrobblerNowPlayingControl/SendNowPlayingControlWidget.swift
]).freeze

SCROBBLE_CONTROL_SOURCES = (CONTROL_SHARED_SOURCES + %w[
  FastScrobblerScrobbleControl/ScrobbleSongControlWidget.swift
]).freeze

IOS_APP_RESOURCES = %w[
  FastScrobbler/Resources/Assets.xcassets
  FastScrobbler/Resources/LaunchScreen.storyboard
].freeze

MAC_APP_RESOURCES = %w[
  FastScrobbler/Resources/Assets.xcassets
].freeze

ROOT_GROUP_PATHS = %w[
  FastScrobbler
  FastScrobblerMac
  FastScrobblerLiveActivity
  FastScrobblerNowPlayingControl
  FastScrobblerScrobbleControl
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
    supported_platforms: "iphoneos iphonesimulator",
    targeted_device_family: "1",
    skip_install: "NO",
    application_extension_api_only: "NO",
    frameworks: %w[
      ActivityKit
      AppIntents
      AuthenticationServices
      BackgroundTasks
      MediaPlayer
      SafariServices
      Security
      StoreKit
      WidgetKit
    ],
  },
  {
    name: "FastScrobblerMac",
    type: :application,
    platform: :osx,
    deployment_target: MACOS_DEPLOYMENT_TARGET,
    bundle_id: MAC_APP_BUNDLE_ID,
    info_plist: "FastScrobblerMac/Info.plist",
    entitlements: "FastScrobblerMac/FastScrobblerMac.entitlements",
    sources: MAC_APP_SOURCES,
    resources: MAC_APP_RESOURCES,
    app_icon: "AppIconMac",
    supported_platforms: "macosx",
    skip_install: "NO",
    application_extension_api_only: "NO",
    frameworks: %w[
      AppKit
      AuthenticationServices
      MediaPlayer
      MusicKit
      Security
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
    resources: [],
    supported_platforms: "iphoneos iphonesimulator",
    targeted_device_family: "1",
    skip_install: "YES",
    application_extension_api_only: "YES",
    frameworks: %w[
      AppIntents
      MediaPlayer
      Security
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
    resources: [],
    supported_platforms: "iphoneos iphonesimulator",
    targeted_device_family: "1",
    skip_install: "YES",
    application_extension_api_only: "YES",
    frameworks: %w[
      AppIntents
      MediaPlayer
      Security
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
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = definition[:bundle_id]
    settings["PRODUCT_NAME"] = definition[:name]
    settings["INFOPLIST_FILE"] = definition[:info_plist]
    settings["GENERATE_INFOPLIST_FILE"] = "NO"
    settings["SWIFT_VERSION"] = SWIFT_VERSION
    settings["MARKETING_VERSION"] = MARKETING_VERSION
    settings["CURRENT_PROJECT_VERSION"] = CURRENT_PROJECT_VERSION
    settings["CODE_SIGN_STYLE"] = "Automatic"
    settings["CODE_SIGN_ENTITLEMENTS"] = definition[:entitlements] if definition[:entitlements]
    settings["SUPPORTED_PLATFORMS"] = definition[:supported_platforms] if definition[:supported_platforms]
    settings["TARGETED_DEVICE_FAMILY"] = definition[:targeted_device_family] if definition[:targeted_device_family]
    settings["APPLICATION_EXTENSION_API_ONLY"] = definition[:application_extension_api_only]
    settings["SKIP_INSTALL"] = definition[:skip_install]
    settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = definition[:app_icon] if definition[:app_icon]
  end
end

def create_shared_scheme(project_path, target)
  scheme = Xcodeproj::XCScheme.new
  scheme.configure_with_targets(target, nil, launch_target: target.product_type == "com.apple.product-type.application")
  scheme.save_as(project_path, target.name, true)
end

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)

refs_by_path = {}
ROOT_GROUP_PATHS.each do |root_path|
  group = project.main_group.new_group(File.basename(root_path), root_path)
  add_tree(group, root_path, refs_by_path)
end

targets = {}
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
  targets[definition[:name]] = target
end

ios_app = targets.fetch("FastScrobbler")
embedded_extensions = [
  targets.fetch("FastScrobblerLiveActivity"),
  targets.fetch("FastScrobblerNowPlayingControl"),
  targets.fetch("FastScrobblerScrobbleControl"),
]

embed_phase = ios_app.new_copy_files_build_phase("Embed App Extensions")
embed_phase.symbol_dst_subfolder_spec = :plug_ins

embedded_extensions.each do |extension_target|
  ios_app.add_dependency(extension_target)
  build_file = embed_phase.add_file_reference(extension_target.product_reference, true)
  build_file.settings = { "ATTRIBUTES" => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
end

project.save

TARGET_DEFINITIONS.each do |definition|
  create_shared_scheme(PROJECT_PATH, targets.fetch(definition[:name]))
end

puts "Wrote #{PROJECT_PATH}"
puts "Targets: #{TARGET_DEFINITIONS.map { |definition| definition[:name] }.join(', ')}"
