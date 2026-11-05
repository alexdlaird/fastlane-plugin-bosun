# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

require_relative "testcase"

class TestPlay < BosunTestCase
  def given_release_notes_template
    @world.write("android/fastlane/metadata/android/en-US/default_release_notes.txt", "Bug fixes.\n")
  end

  def submit(**values)
    run_action(Fastlane::Actions::BosunSubmitPlayProductionAction, :android,
               version: "3.15.1", version_code: "500", metadata_dir: @world.path("android/fastlane/metadata/android"),
               **values)
  end

  def test_next_version_code_takes_the_highest_across_tracks
    # GIVEN
    given_action_returns(:google_play_track_version_codes) do |args|
      raise "no releases" if args[:track] == "beta"

      { "production" => [480], "alpha" => [], "internal" => [499, 497] }[args[:track]]
    end

    # WHEN
    code = run_action(Fastlane::Actions::BosunNextVersionCodeAction, :android)

    # THEN
    assert_equal(500, code)
    assert_equal(%w[production beta alpha internal], action_args(:google_play_track_version_codes).map do |a|
      a[:track]
    end)
    assert_logged("Next version code: 500", "the CI workflow parses this line")
  end

  def test_next_version_code_starts_at_one
    # GIVEN
    given_action_returns(:google_play_track_version_codes, [])

    # WHEN / THEN
    assert_equal(1, run_action(Fastlane::Actions::BosunNextVersionCodeAction, :android))
  end

  def test_internal_upload_uploads_a_completed_release
    # WHEN
    run_action(Fastlane::Actions::BosunUploadToPlayInternalAction, :android, aab: "app.aab", version: "3.15.1")

    # THEN
    assert_equal([{ aab: "app.aab", track: "internal", version_name: "3.15.1", skip_upload_apk: true,
                    skip_upload_metadata: true, skip_upload_images: true, skip_upload_screenshots: true,
                    release_status: "completed" }], action_args(:upload_to_play_store))
  end

  def test_submitting_stamps_the_changelog_and_promotes_a_completed_release
    # GIVEN
    given_release_notes_template
    given_action_returns(:google_play_track_version_codes, [500])

    # WHEN
    submit(submit_for_review: true)

    # THEN
    assert_equal("Bug fixes.\n", File.read(@world.path("android/fastlane/metadata/android/en-US/changelogs/500.txt")))
    assert_equal([{ metadata_path: @world.path("android/fastlane/metadata/android"), track: "internal",
                    track_promote_to: "production", version_code: "500", track_promote_release_status: "completed",
                    skip_upload_apk: true, skip_upload_aab: true, skip_upload_metadata: false,
                    skip_upload_images: true, skip_upload_screenshots: true }], action_args(:upload_to_play_store))
    assert_empty(calls(:supply, :update_track), "the version code is already on Internal")
  end

  def test_staging_promotes_a_draft_without_checking_reviews
    # GIVEN
    given_release_notes_template
    given_action_returns(:google_play_track_version_codes, [500])
    @world.play_client.production_releases = [Bosun::Fakes.release("3.15.0", "IN_REVIEW")]

    # WHEN
    submit(submit_for_review: false, push_store_assets: true)

    # THEN
    args = action_args(:upload_to_play_store).first
    assert_equal("draft", args[:track_promote_release_status])
    assert_equal([false, false], args.values_at(:skip_upload_images, :skip_upload_screenshots))
    assert_empty(calls(:supply, :list_application_track_releases))
  end

  def test_submitting_is_refused_while_a_release_is_in_review
    %w[IN_REVIEW APPROVED_NOT_PUBLISHED].each do |state|
      # GIVEN
      setup
      given_release_notes_template
      @world.play_client.production_releases = [Bosun::Fakes.release("3.15.0", state)]

      # WHEN / THEN
      assert_user_error(/3\.15\.0 \(`RELEASE_LIFECYCLE_STATE_#{state}`\)/) { submit(submit_for_review: true) }
      assert_empty(action_args(:upload_to_play_store))
      teardown
    end
  end

  def test_replacing_the_review_skips_the_check
    # GIVEN
    given_release_notes_template
    given_action_returns(:google_play_track_version_codes, [500])
    @world.play_client.production_releases = [Bosun::Fakes.release("3.15.0", "IN_REVIEW")]

    # WHEN
    submit(submit_for_review: true, replace_in_review: true)

    # THEN
    assert_empty(calls(:supply, :list_application_track_releases))
    assert_equal("completed", action_args(:upload_to_play_store).first[:track_promote_release_status],
                 "Play cancels the review in progress and reviews this release")
  end

  def test_settled_releases_do_not_block
    # GIVEN
    given_release_notes_template
    given_action_returns(:google_play_track_version_codes, [500])
    @world.play_client.production_releases = %w[DRAFT NOT_SENT_FOR_REVIEW NOT_APPROVED PUBLISHED].map do |state|
      Bosun::Fakes.release("3.14.#{state.size}", state)
    end

    # WHEN
    submit(submit_for_review: true)

    # THEN
    assert_equal(1, action_args(:upload_to_play_store).size)
  end

  def test_a_version_code_gone_from_internal_is_restaged_as_a_draft
    # GIVEN
    given_release_notes_template
    given_action_returns(:google_play_track_version_codes, [512])

    # WHEN
    submit(submit_for_review: false)

    # THEN
    assert_equal([{ track: "internal", releases: [{ name: "3.15.1", status: "draft", version_codes: [500] }] }],
                 calls(:supply, :update_track).map(&:last))
    assert_equal(1, calls(:supply, :commit_current_edit!).size)
    assert_equal({ cwd: File.realpath(@world.path("android")) }, calls(:supply, :make_from_config).first.last,
                 "Play's client resolves the Appfile's json_key_file from the project folder")
  end

  def test_a_missing_release_notes_template_fails
    # WHEN / THEN
    assert_user_error(/Missing .*default_release_notes.txt/) { submit(submit_for_review: true) }
  end
end
