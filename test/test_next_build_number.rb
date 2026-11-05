# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

require_relative "testcase"

class TestNextBuildNumber < BosunTestCase
  def next_build_number(**values)
    run_action(Fastlane::Actions::BosunNextBuildNumberAction, :ios, api_key: API_KEY, **values)
  end

  def test_scoped_to_a_version_adds_one_to_its_latest_build
    # GIVEN
    given_action_returns(:latest_testflight_build_number, 7)

    # WHEN
    number = next_build_number(version: "3.15.1", scope_to_version: true)

    # THEN
    assert_equal(8, number)
    assert_equal([{ api_key: API_KEY, version: "3.15.1", initial_build_number: 0 }],
                 action_args(:latest_testflight_build_number))
    assert_logged("Next build number for 3.15.1: 8")
  end

  def test_app_wide_looks_up_every_version
    # GIVEN
    given_action_returns(:latest_testflight_build_number, 41)

    # WHEN
    number = next_build_number(version: "1.0", scope_to_version: false)

    # THEN
    assert_equal(42, number)
    assert_equal([{ api_key: API_KEY, initial_build_number: 0 }], action_args(:latest_testflight_build_number),
                 "an app-wide lookup doesn't name the version")
    assert_logged("Next build number for 1.0: 42")
  end

  def test_floor_raises_the_number
    # GIVEN
    given_action_returns(:latest_testflight_build_number, 3)

    # WHEN
    number = next_build_number(version: "1.0", floor: "120")

    # THEN
    assert_equal(120, number)
  end

  def test_floor_below_the_next_number_is_ignored
    # GIVEN
    given_action_returns(:latest_testflight_build_number, 300)

    # WHEN
    number = next_build_number(version: "1.0", floor: "120")

    # THEN
    assert_equal(301, number)
  end

  def test_without_a_version_logs_the_plain_line
    # GIVEN
    given_action_returns(:latest_testflight_build_number, 0)

    # WHEN
    number = next_build_number

    # THEN
    assert_equal(1, number)
    assert_logged("Next build number: 1", "the CI workflow parses this line")
  end
end
