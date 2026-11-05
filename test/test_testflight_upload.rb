# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

require_relative "testcase"

class TestTestflightUpload < BosunTestCase
  REJECTIONS = ["This bundle is invalid", "is closed for new build submissions", "bundle version must be higher",
                "ATTRIBUTE.INVALID.DUPLICATE"].freeze

  def upload(**values)
    defaults = { api_key: API_KEY, ipa: "../build/ios/ipa/App.ipa", build_number: "5", version: "3.15.1",
                 wait_processing_timeout_duration: 3600 }
    run_action(Fastlane::Actions::BosunTestflightUploadAction, :ios, **defaults, **values)
  end

  def given_upload_fails(message)
    given_action_raises(:upload_to_testflight, StandardError.new(message))
  end

  def test_uploads_with_the_given_settings
    # WHEN
    upload(skip_submission: true, wait_processing_timeout_duration: 1800)

    # THEN
    assert_equal([{ api_key: API_KEY, ipa: "../build/ios/ipa/App.ipa", skip_submission: true,
                    skip_waiting_for_build_processing: false, wait_processing_timeout_duration: 1800,
                    distribute_external: false }], action_args(:upload_to_testflight))
  end

  def test_a_false_positive_passes_once_the_build_is_listed
    # GIVEN
    given_upload_fails("Failed with error: WILL RETRY PART 3")
    given_builds_appear_after(2)

    # WHEN
    upload(verify_by_version: true)

    # THEN
    assert_equal([30, 30], calls(:sleep).map { |_, seconds| seconds }, "polls every 30 seconds until it's listed")
    assert_equal({ app_id: "app-id", build_number: "5", limit: 1, version: "3.15.1" },
                 calls(:spaceship, :builds).last.last)
  end

  def test_a_build_that_never_appears_reraises_after_twenty_polls
    # GIVEN
    given_upload_fails("Failed with error: something")

    # WHEN
    error = assert_raises(StandardError) { upload(verify_by_version: true) }

    # THEN
    assert_equal("Failed with error: something", error.message)
    assert_equal(20, calls(:sleep).size)
  end

  def test_a_processing_timeout_is_reraised_when_configured
    # GIVEN
    given_upload_fails("BuildWatcher exceeded the wait")
    given_builds(:build)

    # WHEN / THEN
    assert_raises(StandardError) { upload(reraise_build_watcher: true, verify_by_version: true) }
    assert_empty(calls(:spaceship, :builds), "a processing timeout is never excused by the build being listed")
  end

  def test_a_processing_timeout_is_excused_without_the_option
    # GIVEN
    given_upload_fails("BuildWatcher exceeded the wait")
    given_builds(:build)

    # WHEN
    upload(verify_by_version: true)

    # THEN
    refute_empty(calls(:spaceship, :builds))
  end

  def test_each_rejection_message_is_reraised_without_looking_for_the_build
    REJECTIONS.each do |rejection|
      # GIVEN
      setup
      given_upload_fails("ERROR: #{rejection}")
      given_builds(:build)

      # WHEN / THEN
      assert_raises(StandardError) { upload(rejection_messages: REJECTIONS, verify_by_version: true) }
      assert_empty(calls(:spaceship, :builds), "#{rejection} is an outright rejection")
      teardown
    end
  end

  def test_a_rejection_not_in_the_list_looks_for_the_build
    # GIVEN
    given_upload_fails("ERROR: ATTRIBUTE.INVALID.DUPLICATE")
    given_builds(:build)

    # WHEN
    upload(rejection_messages: ["bundle version must be higher"], verify_by_version: true)

    # THEN
    refute_empty(calls(:spaceship, :builds))
  end

  def test_verifying_by_version_needs_the_version
    # GIVEN
    given_upload_fails("Failed with error: something")
    given_builds(:build)

    # WHEN / THEN
    assert_raises(StandardError) { upload(version: nil, verify_by_version: true) }
    assert_empty(calls(:spaceship, :builds))
  end

  def test_verifying_any_version_looks_up_the_build_number_alone
    # GIVEN
    given_upload_fails("Failed with error: something")
    given_builds(:build)

    # WHEN
    upload(version: nil, verify_by_version: false)

    # THEN
    assert_equal({ app_id: "app-id", build_number: "5", limit: 1 }, calls(:spaceship, :builds).last.last)
  end

  def test_without_a_build_number_the_error_is_reraised
    # GIVEN
    given_upload_fails("Failed with error: something")

    # WHEN / THEN
    assert_raises(StandardError) { upload(build_number: nil) }
  end

  def test_a_failed_lookup_reads_as_not_uploaded
    # GIVEN
    given_upload_fails("Failed with error: something")
    @world.builds = ->(_filter) { raise "App Store Connect is down" }

    # WHEN / THEN
    assert_raises(StandardError) { upload(verify_by_version: true) }
    assert_equal(20, calls(:sleep).size)
  end
end
