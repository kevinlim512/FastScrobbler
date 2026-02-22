#!/usr/bin/env ruby
# frozen_string_literal: true

require "xcodeproj"
require "fileutils"

PROJECT_NAME = "FastScrobbler"
IOS_DEPLOYMENT_TARGET = "17.0"

project_path = "#{PROJECT_NAME}.xcodeproj"

FileUtils.rm_rf(project_path)

project = Xcodeproj::Project.new(project_path)

main_group = project.main_group
app_group = main_group.new_group(PROJECT_NAME, PROJECT_NAME)

def add_files_recursively(group, dir_path)
  Dir.children(dir_path).sort.each do |child|
    next if child.start_with?(".")

    full = File.join(dir_path, child)
    if File.directory?(full)
      if child.end_with?(".xcassets")
        group.new_file(child)
        next
      end
      subgroup = group.new_group(child, child)
      add_files_recursively(subgroup, full)
    else
      group.new_file(child)
    end
  end
end

add_files_recursively(app_group, PROJECT_NAME)

target = project.new_target(:application, PROJECT_NAME, :ios, IOS_DEPLOYMENT_TARGET)

target.build_configurations.each do |config|
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.example.#{PROJECT_NAME}"
  config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = IOS_DEPLOYMENT_TARGET
  config.build_settings["INFOPLIST_FILE"] = "#{PROJECT_NAME}/Info.plist"
  config.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  config.build_settings["TARGETED_DEVICE_FAMILY"] = "1"
  config.build_settings["SWIFT_VERSION"] = "5.0"
  config.build_settings["CURRENT_PROJECT_VERSION"] = "1"
  config.build_settings["MARKETING_VERSION"] = "1.0"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "NO"
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
end

# Add sources/resources to build phases
def file_refs_in_group(group)
  refs = []
  group.files.each { |f| refs << f }
  group.groups.each { |g| refs.concat(file_refs_in_group(g)) }
  refs
end

all_refs = file_refs_in_group(app_group)
swift_refs = all_refs.select { |r| r.path.end_with?(".swift") }
resource_refs = all_refs.select do |r|
  r.path.end_with?(".storyboard") || r.path.end_with?(".xcassets")
end

swift_refs.each { |ref| target.add_file_references([ref]) }
resource_refs.each { |ref| target.add_resources([ref]) }

# Link required system frameworks.
frameworks_group = project.frameworks_group
[
  "AuthenticationServices.framework",
  "MediaPlayer.framework",
  "Security.framework",
].each do |fw|
  ref = frameworks_group.new_file("/System/Library/Frameworks/#{fw}")
  target.frameworks_build_phase.add_file_reference(ref)
end

project.save

puts "Wrote #{project_path}"
