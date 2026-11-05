# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

require "minitest/autorun"
require "fastlane"
require "supply"
require "fastlane/plugin/bosun"
require_relative "support/world"

class BosunTestCase < Minitest::Test
  API_KEY = { key_id: "key-id", issuer_id: "issuer-id", key: "key" }.freeze

  def setup
    @world = Bosun::World.new
  end

  def teardown
    @world.cleanup
  end

  # Runs an action the way fastlane does: from the platform's project folder, with other_action calling through.
  def run_action(action, platform, **values)
    config = FastlaneCore::Configuration.create(action.available_options, values)
    proxy = @world.proxy
    @world.enter do
      Bosun::Stubs.with([[action, :other_action, -> { proxy }]]) do
        Dir.chdir(@world.path(platform.to_s)) { action.run(config) }
      end
    end
  end

  def given_action_returns(name, value = nil, &block)
    @world.recorder.responses[name] = block || ->(_args) { value }
  end

  def given_action_raises(name, error)
    @world.recorder.responses[name] = ->(_args) { raise error }
  end

  def given_app_store_versions(*versions)
    @world.app.versions = versions
  end

  def given_review_submission(state, &on_cancel)
    @world.app.review_submission = Bosun::Fakes::ReviewSubmission.new(@world.recorder, state, on_cancel: on_cancel)
  end

  def given_builds(*builds)
    @world.builds = builds
  end

  def given_builds_appear_after(polls)
    seen = 0
    @world.builds = lambda do |_filter|
      seen += 1
      seen > polls ? [:build] : []
    end
  end

  def calls(kind, name = nil)
    @world.recorder.of(kind, name)
  end

  def action_args(name)
    calls(:action, name).map(&:last)
  end

  def assert_logged(text, message = nil)
    assert_includes(calls(:ui).map(&:last), text, message)
  end

  def assert_user_error(pattern, &)
    error = assert_raises(FastlaneCore::Interface::FastlaneError, &)
    assert_match(pattern, error.message)
    error
  end

  def version(version_string, **states)
    Bosun::Fakes::AppStoreVersion.new(version_string, **states)
  end
end
