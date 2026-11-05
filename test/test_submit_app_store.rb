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

  def waiting_for_review(version_string)
    version(version_string, app_store_state: "WAITING_FOR_REVIEW", app_version_state: "WAITING_FOR_REVIEW")
  end

  def withdraw(*versions)
    lambda do |_submission|
      versions.each do |withdrawn|
        withdrawn.app_store_state = "DEVELOPER_REJECTED"
        withdrawn.app_version_state = "DEVELOPER_REJECTED"
      end
    end
  end

  def test_replacing_withdraws_another_version_waiting_for_review_then_submits
    # GIVEN
    waiting = waiting_for_review("3.14.6")
    given_app_store_versions(waiting)
    given_review_submission("WAITING_FOR_REVIEW", &withdraw(waiting))

    # WHEN
    submit(submit_for_review: true, replace_waiting_for_review: true, automatic_release: true)

    # THEN
    assert_equal([[:spaceship, :cancel_submission, { state: "WAITING_FOR_REVIEW" }]],
                 calls(:spaceship, :cancel_submission))
    assert_equal(1, uploads.size)
    assert_equal(true, uploads.first[:submit_for_review])
    names = @world.recorder.calls.map { |_, name, _| name }
    assert_operator(names.index(:cancel_submission), :<, names.index(:upload_to_app_store),
                    "the waiting version is withdrawn before the listing changes")
    assert_empty(calls(:sleep), "no wait once App Store Connect has withdrawn it")
  end

  def test_replacing_resubmits_the_same_version_waiting_for_review
    # GIVEN
    waiting = waiting_for_review("3.15.1")
    given_app_store_versions(waiting)
    given_review_submission("WAITING_FOR_REVIEW", &withdraw(waiting))

    # WHEN
    submit(submit_for_review: true, replace_waiting_for_review: true, automatic_release: true)

    # THEN
    assert_equal(1, calls(:spaceship, :cancel_submission).size)
    assert_equal(1, uploads.size)
  end

  def test_replacing_waits_until_app_store_connect_withdraws_the_version
    # GIVEN
    waiting = waiting_for_review("3.14.6")
    given_app_store_versions(waiting)
    polls_left = nil
    given_review_submission("WAITING_FOR_REVIEW") { polls_left = 2 }
    waiting.define_singleton_method(:app_version_state) do
      next "WAITING_FOR_REVIEW" if polls_left.nil?

      polls_left -= 1
      polls_left.negative? ? "DEVELOPER_REJECTED" : "WAITING_FOR_REVIEW"
    end

    # WHEN
    submit(submit_for_review: true, replace_waiting_for_review: true, automatic_release: true)

    # THEN
    assert_equal([15, 15], calls(:sleep).map { |_, seconds| seconds })
    assert_equal(1, uploads.size)
  end

  def test_replacing_fails_when_the_version_is_never_withdrawn
    # GIVEN
    given_app_store_versions(waiting_for_review("3.14.6"))
    given_review_submission("WAITING_FOR_REVIEW")

    # WHEN / THEN
    assert_user_error(/still waiting for review after cancelling/) do
      submit(submit_for_review: true, replace_waiting_for_review: true, automatic_release: true)
    end
    assert_equal(20, calls(:sleep).size)
    assert_empty(uploads)
  end

  def test_replacing_leaves_a_submission_apple_started_reviewing
    # GIVEN
    given_app_store_versions(waiting_for_review("3.14.6"))
    given_review_submission("IN_REVIEW")

    # WHEN / THEN
    assert_user_error(/now `IN_REVIEW`, so it wasn't cancelled/) do
      submit(submit_for_review: true, replace_waiting_for_review: true, automatic_release: true)
    end
    assert_empty(calls(:spaceship, :cancel_submission))
    assert_empty(uploads)
  end

  def test_replacing_never_withdraws_a_version_past_waiting_for_review
    %w[READY_FOR_REVIEW IN_REVIEW WAITING_FOR_EXPORT_COMPLIANCE ACCEPTED PENDING_APPLE_RELEASE
       PENDING_DEVELOPER_RELEASE PROCESSING_FOR_DISTRIBUTION].each do |state|
      # GIVEN
      setup
      given_app_store_versions(version("3.14.6", app_version_state: state))
      given_review_submission("IN_REVIEW")

      # WHEN / THEN
      assert_user_error(/3\.14\.6 \(`#{state}`\)/) do
        submit(submit_for_review: true, replace_waiting_for_review: true, automatic_release: true)
      end
      assert_empty(calls(:spaceship, :cancel_submission), state)
      teardown
    end
  end

  def test_replacing_never_withdraws_the_same_version_in_review
    # GIVEN
    given_app_store_versions(version("3.15.1", app_store_state: "IN_REVIEW", app_version_state: "IN_REVIEW"))
    given_review_submission("IN_REVIEW")

    # WHEN / THEN
    assert_user_error(/in state `IN_REVIEW`/) do
      submit(submit_for_review: true, replace_waiting_for_review: true, automatic_release: true)
    end
    assert_empty(calls(:spaceship, :cancel_submission))
  end

  def test_staging_never_withdraws_a_version_waiting_for_review
    # GIVEN
    given_app_store_versions(waiting_for_review("3.14.6"))
    given_review_submission("WAITING_FOR_REVIEW")

    # WHEN / THEN
    assert_user_error(/3\.14\.6 \(`WAITING_FOR_REVIEW`\)/) do
      submit(submit_for_review: false, replace_waiting_for_review: true, automatic_release: true)
    end
    assert_empty(calls(:spaceship, :cancel_submission))
  end

  def test_replacing_with_nothing_waiting_cancels_nothing
    # GIVEN
    given_review_submission("UNRESOLVED_ISSUES")

    # WHEN
    submit(submit_for_review: true, replace_waiting_for_review: true, automatic_release: true)

    # THEN
    assert_empty(calls(:spaceship, :get_in_progress_review_submission))
    assert_equal(1, uploads.size)
  end

  def test_staging_without_the_build_listed_fails
    # WHEN / THEN
    assert_user_error(/not found in App Store Connect/) { submit(automatic_release: true) }
  end
end
