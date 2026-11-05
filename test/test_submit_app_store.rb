# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

require_relative "testcase"

class TestSubmitAppStore < BosunTestCase
  def submit(**values)
    run_action(Fastlane::Actions::BosunSubmitAppStoreAction, :ios,
               api_key: API_KEY, version: "3.15.1", build_number: "5", **values)
  end

  def uploads
    action_args(:upload_to_app_store)
  end

  def test_staging_uploads_the_listing_and_attaches_the_build
    # GIVEN
    given_builds(Struct.new(:id).new("build-id"))

    # WHEN
    submit(submit_for_review: false, automatic_release: true, listing_options: { privacy_url: { "en-US" => "x" } })

    # THEN
    assert_equal([{ api_key: API_KEY, app_version: "3.15.1", build_number: "5", skip_binary_upload: true,
                    skip_screenshots: true, overwrite_screenshots: true, skip_metadata: false,
                    submit_for_review: false, automatic_release: true, force: true,
                    precheck_include_in_app_purchases: false, privacy_url: { "en-US" => "x" } }], uploads)
    assert_equal([[:spaceship, :select_build, { build_id: "build-id" }]], calls(:spaceship, :select_build))
  end

  def test_submitting_lets_deliver_attach_the_build
    # WHEN
    submit(submit_for_review: true, automatic_release: true)

    # THEN
    assert_equal(true, uploads.first[:submit_for_review])
    assert_empty(calls(:spaceship, :select_build), "deliver attaches the build itself when it submits")
  end

  def test_submitting_with_fresh_screenshots_submits_once_they_finish_processing
    # GIVEN
    attempts = 0
    given_action_returns(:upload_to_app_store) do |args|
      next unless args[:submit_for_review]

      attempts += 1
      raise Spaceship::UnexpectedResponse, "Screenshot uploads still in progress" if attempts < 3
    end

    # WHEN
    submit(submit_for_review: true, push_store_assets: true, automatic_release: false)

    # THEN
    assert_equal(false, uploads.first[:submit_for_review], "fresh screenshots can't be submitted with the listing")
    assert_equal(false, uploads.first[:skip_screenshots])
    assert_equal(3, uploads.count { |args| args[:submit_for_review] })
    assert(uploads.all? { |args| args[:automatic_release] == false })
    assert_equal([30, 30], calls(:sleep).map { |_, seconds| seconds })
  end

  def test_a_version_already_submitted_is_refused
    # GIVEN
    given_app_store_versions(version("3.15.1", app_store_state: "WAITING_FOR_REVIEW"))

    # WHEN / THEN
    assert_user_error(/in state `WAITING_FOR_REVIEW`/) { submit(automatic_release: true) }
    assert_empty(uploads)
  end

  def test_another_version_in_flight_is_refused_before_anything_changes
    # GIVEN
    given_app_store_versions(version("3.14.6", app_store_state: "WAITING_FOR_REVIEW",
                                               app_version_state: "WAITING_FOR_REVIEW"))

    # WHEN / THEN
    assert_user_error(/3\.14\.6 \(`WAITING_FOR_REVIEW`\)/) { submit(automatic_release: true) }
    assert_empty(uploads, "staging now would rename the in-flight version")
  end

  def test_each_in_flight_state_is_refused
    %w[READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW WAITING_FOR_EXPORT_COMPLIANCE ACCEPTED PENDING_APPLE_RELEASE
       PENDING_DEVELOPER_RELEASE PROCESSING_FOR_DISTRIBUTION].each do |state|
      # GIVEN
      setup
      given_app_store_versions(version("3.14.6", app_version_state: state))

      # WHEN / THEN
      assert_user_error(/3\.14\.6/) { submit(automatic_release: true) }
      teardown
    end
  end

  def test_settled_versions_do_not_block
    # GIVEN
    given_app_store_versions(
      version("3.14.5", app_store_state: "READY_FOR_SALE", app_version_state: "READY_FOR_DISTRIBUTION"),
      version("3.14.6", app_version_state: "REJECTED")
    )
    given_builds(Struct.new(:id).new("build-id"))

    # WHEN
    submit(automatic_release: true)

    # THEN
    assert_equal(1, uploads.size)
  end

  def test_a_listing_lambda_is_built_after_the_checks_from_the_fastlane_folder
    # GIVEN
    given_builds(Struct.new(:id).new("build-id"))
    built_in = nil
    listing = lambda do
      built_in = Dir.pwd
      @world.recorder.record(:listing, :built)
      { app_review_information: { notes: "notes" } }
    end

    # WHEN
    submit(automatic_release: true, listing_options: listing)

    # THEN
    assert_equal(File.realpath(@world.path("ios/fastlane")), File.realpath(built_in),
                 "the lambda's relative paths resolve as they did in the lane")
    kinds = @world.recorder.calls.map { |kind, name, _| [kind, name] }
    assert_operator(kinds.index(%i[listing built]), :>, kinds.rindex(%i[spaceship get_app_store_versions]))
    assert_equal({ notes: "notes" }, uploads.first[:app_review_information])
  end

  def test_a_listing_lambda_is_not_built_for_a_refused_version
    # GIVEN
    given_app_store_versions(version("3.15.1", app_store_state: "IN_REVIEW", app_version_state: "IN_REVIEW"))
    listing = -> { raise "the listing was built" }

    # WHEN / THEN
    assert_user_error(/IN_REVIEW/) { submit(automatic_release: true, listing_options: listing) }
  end

  def test_staging_without_the_build_listed_fails
    # WHEN / THEN
    assert_user_error(/not found in App Store Connect/) { submit(automatic_release: true) }
  end
end
