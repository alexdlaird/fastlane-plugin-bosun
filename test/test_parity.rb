# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

require_relative "testcase"
require_relative "support/fastfile_sandbox"

# Moving an app onto bosun must not change what its lanes do. For each app in BOSUN_PARITY_DIR
# (<app>/<platform>/reference.Fastfile, the app's Fastfile today, and candidate.Fastfile, the same lanes on bosun),
# every scenario runs against both, and everything they do to the outside world must match call for call: fastlane
# actions and their arguments, App Store Connect and Play calls, sleeps, files written, the log lines CI parses, and
# the result or error. Skipped when BOSUN_PARITY_DIR isn't set (the apps' Fastfiles aren't part of this repo).
class TestParity < BosunTestCase
  PARITY_DIR = ENV.fetch("BOSUN_PARITY_DIR", nil)
  REJECTIONS = ["This bundle is invalid", "is closed for new build submissions", "bundle version must be higher",
                "ATTRIBUTE.INVALID.DUPLICATE"].freeze
  PARSED_LOG_LINE = /\ANext (build number|version code)/

  IOS = {
    next_build_number: [
      ["a version", { version: "3.15.1" }, nil],
      ["a version and floor", { version: "1.0", floor: "120" }, nil]
    ],
    deploy_testflight: [
      ["success", { version: "3.15.1", build_number: "5" }, nil],
      ["false positive", { version: "3.15.1", build_number: "5" }, :false_positive],
      ["never listed", { version: "3.15.1", build_number: "5" }, :never_listed],
      ["processing timeout", { version: "3.15.1", build_number: "5" }, :build_watcher],
      *REJECTIONS.map { |rejection| ["rejection #{rejection}", { version: "3.15.1", build_number: "5" }, rejection] },
      ["no build number", { version: "3.15.1" }, :false_positive],
      ["no version", { build_number: "5" }, :false_positive],
      ["lookup error", { version: "3.15.1", build_number: "5" }, :lookup_error]
    ],
    submit_appstore: [
      ["stage", { version: "3.15.1", build_number: "5" }, :listed_build],
      ["stage with assets", { version: "3.15.1", build_number: "5", push_store_assets: "true" }, :listed_build],
      ["submit", { version: "3.15.1", build_number: "5", submit_for_review: "true" }, nil],
      ["submit with assets", { version: "3.15.1", build_number: "5", submit_for_review: "true",
                               push_store_assets: "true" }, :screenshots_processing],
      ["locked version", { version: "3.15.1", build_number: "5", submit_for_review: "true" }, :locked],
      ["version in flight", { version: "3.15.1", build_number: "5", submit_for_review: "true" }, :in_flight],
      ["build not listed", { version: "3.15.1", build_number: "5" }, nil],
      ["no build number", { version: "3.15.1" }, nil]
    ]
  }.freeze

  ANDROID = {
    next_version_code: [["codes", {}, :version_codes]],
    deploy_internal: [
      ["default aab", { version: "3.15.1" }, nil],
      ["given aab", { version: "3.15.1", aab_path: "app.aab" }, nil]
    ],
    submit_production: [
      ["submit", { version: "3.15.1", version_code: "500", submit_for_review: "true" }, :staged],
      ["submit with assets", { version: "3.15.1", version_code: "500", submit_for_review: "true",
                               push_store_assets: "true" }, :staged],
      ["stage", { version: "3.15.1", version_code: "500" }, :staged],
      ["restage", { version: "3.15.1", version_code: "500", submit_for_review: "true" }, :replaced],
      ["in review", { version: "3.15.1", version_code: "500", submit_for_review: "true" }, :in_review],
      ["approved", { version: "3.15.1", version_code: "500", submit_for_review: "true" }, :approved],
      ["staged while in review", { version: "3.15.1", version_code: "500" }, :in_review],
      ["no template", { version: "3.15.1", version_code: "500", submit_for_review: "true" }, :no_template],
      ["no version code", { version: "3.15.1" }, nil]
    ]
  }.freeze

  def setup
    skip("BOSUN_PARITY_DIR isn't set") unless PARITY_DIR
    super
  end

  def test_every_app_matches_its_reference
    pairs = Dir[File.join(PARITY_DIR, "*", "*", "reference.Fastfile")].map { |path| File.dirname(path) }
    refute_empty(pairs, "no <app>/<platform>/reference.Fastfile in #{PARITY_DIR}")

    differences = pairs.flat_map { |pair| compare(pair) }

    assert_empty(differences, differences.join("\n\n"))
  end

  private

  def compare(pair)
    platform = File.basename(pair).to_sym
    scenarios = platform == :ios ? IOS : ANDROID
    scenarios.flat_map do |lane, cases|
      cases.filter_map do |label, options, condition|
        reference = outcome(pair, "reference.Fastfile", platform, lane, options, condition)
        next if reference == :no_lane

        candidate = outcome(pair, "candidate.Fastfile", platform, lane, options, condition)
        next if reference == candidate

        "#{File.basename(File.dirname(pair))}/#{platform} #{lane} (#{label}):\n  " \
          "reference: #{reference.inspect}\n  candidate: #{candidate.inspect}"
      end
    end
  end

  def outcome(pair, file, platform, lane, options, condition)
    world = Bosun::World.new
    fastfile = world.path(platform.to_s, "fastlane", "Fastfile")
    FileUtils.cp(File.join(pair, file), fastfile)
    sandbox = Bosun::FastfileSandbox.new(world, fastfile)
    return :no_lane unless sandbox.instance_variable_get(:@lanes).key?(lane)

    arrange(world, condition)
    result = begin
      [:returned, sandbox.run(lane, options)]
    rescue StandardError => e
      [:raised, e.class.name]
    end
    normalize([result, observed(world)], world)
  ensure
    world&.cleanup
  end

  # Keyword arguments are compared regardless of order, and the two runs' temporary project folders as one.
  def normalize(value, world)
    case value
    when Hash then value.map { |key, item| [key, normalize(item, world)] }.sort_by { |key, _| key.to_s }
    when Array then value.map { |item| normalize(item, world) }
    when String
      [File.realpath(world.project_dir), world.project_dir].reduce(value) { |text, dir| text.gsub(dir, "<project>") }
    else value
    end
  end

  def observed(world)
    world.recorder.calls.reject { |kind, _, text| kind == :ui && !PARSED_LOG_LINE.match?(text.to_s) } +
      Dir[world.path("**", "changelogs", "*")].map { |file| [:file, File.basename(file), File.read(file)] }
  end

  def arrange(world, condition)
    world.write("build/ios/ipa/Runner.ipa", "")
    world.write("public.env", "SITE_URL=https://example.com/\n")
    world.write("ios/fastlane/metadata/review_information/notes.txt", "Review notes\n")
    world.write("android/fastlane/metadata/android/en-US/default_release_notes.txt", "Bug fixes.\n")
    %w[FIRST_NAME LAST_NAME EMAIL PHONE].each { |field| ENV["APP_REVIEW_#{field}"] = "review-#{field.downcase}" }
    world.app.versions = [Bosun::Fakes::AppStoreVersion.new("3.14.5", app_store_state: "READY_FOR_SALE",
                                                                      app_version_state: "READY_FOR_DISTRIBUTION",
                                                                      review_detail: Bosun::Fakes::ReviewDetail
                                                                                     .new("demo", "secret"))]
    world.recorder.responses[:app_store_connect_api_key] = ->(_args) { { key_id: "key-id" } }
    world.recorder.responses[:latest_testflight_build_number] = ->(_args) { 7 }
    arrange_condition(world, condition)
  end

  def arrange_condition(world, condition)
    recorder = world.recorder
    case condition
    when :false_positive
      fail_upload(recorder, "Failed with error: WILL RETRY PART 3")
      polls = 0
      world.builds = lambda do |_filter|
        polls += 1
        polls > 2 ? [:build] : []
      end
    when :never_listed
      fail_upload(recorder, "Failed with error: something")
    when :build_watcher
      fail_upload(recorder, "BuildWatcher exceeded the wait")
      world.builds = [:build]
    when String
      fail_upload(recorder, "ERROR: #{condition}")
      world.builds = [:build]
    when :lookup_error
      fail_upload(recorder, "Failed with error: something")
      world.builds = ->(_filter) { raise "App Store Connect is down" }
    when :listed_build
      world.builds = [Struct.new(:id).new("build-id")]
    when :screenshots_processing
      attempts = 0
      recorder.responses[:upload_to_app_store] = lambda do |args|
        next unless args[:submit_for_review] && args[:skip_metadata]

        attempts += 1
        raise Spaceship::UnexpectedResponse, "Screenshot uploads still in progress" if attempts < 3
      end
    when :locked
      world.app.versions << Bosun::Fakes::AppStoreVersion.new("3.15.1", app_store_state: "WAITING_FOR_REVIEW",
                                                                        app_version_state: "WAITING_FOR_REVIEW")
    when :in_flight
      world.app.versions << Bosun::Fakes::AppStoreVersion.new("3.14.6", app_store_state: "WAITING_FOR_REVIEW",
                                                                        app_version_state: "WAITING_FOR_REVIEW")
    when :version_codes
      recorder.responses[:google_play_track_version_codes] = lambda do |args|
        raise "no releases" if args[:track] == "beta"

        { "production" => [480], "alpha" => [], "internal" => [499, 497] }[args[:track]]
      end
    when :staged, :in_review, :approved
      recorder.responses[:google_play_track_version_codes] = ->(_args) { [500] }
      state = { in_review: "IN_REVIEW", approved: "APPROVED_NOT_PUBLISHED" }[condition]
      world.play_client.production_releases = [Bosun::Fakes.release("3.15.0", state)] if state
    when :replaced
      recorder.responses[:google_play_track_version_codes] = ->(_args) { [512] }
    when :no_template
      FileUtils.rm_f(world.path("android/fastlane/metadata/android/en-US/default_release_notes.txt"))
    end
  end

  def fail_upload(recorder, message)
    recorder.responses[:upload_to_testflight] = ->(_args) { raise StandardError, message }
  end
end
