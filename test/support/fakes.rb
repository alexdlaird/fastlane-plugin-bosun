# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

module Bosun
  module Fakes
    Release = Struct.new(:release_name, :release_lifecycle_state)
    ReleaseList = Struct.new(:releases)

    # Records everything the code under test does to the outside world (fastlane actions, App Store Connect, Play,
    # log lines, sleeps), in order, so two implementations can be compared call for call.
    class Recorder
      attr_reader :calls, :responses

      def initialize
        @calls = []
        @responses = {}
      end

      def record(kind, name, args = nil)
        @calls << [kind, name, args]
        nil
      end

      def action(name, args)
        record(:action, name, args)
        response = @responses[name]
        response.respond_to?(:call) ? response.call(args) : response
      end

      def of(kind, name = nil)
        @calls.select { |call_kind, call_name, _| call_kind == kind && (name.nil? || call_name == name) }
      end
    end

    # Stands in for other_action (in an action) or the fastlane runner (in a Fastfile): every action call is recorded.
    class ActionProxy < BasicObject
      def initialize(recorder)
        @recorder = recorder
      end

      def method_missing(name, *args, **kwargs)
        @recorder.action(name, kwargs.empty? ? args.first : kwargs)
      end

      def respond_to_missing?(_name, _include_private = false)
        true
      end
    end

    class EditVersion
      def initialize(recorder)
        @recorder = recorder
      end

      def select_build(build_id:)
        @recorder.record(:spaceship, :select_build, { build_id: build_id })
      end
    end

    class ReviewDetail
      attr_reader :demo_account_name, :demo_account_password

      def initialize(name, password)
        @demo_account_name = name
        @demo_account_password = password
      end
    end

    class AppStoreVersion
      attr_reader :version_string, :review_detail
      attr_accessor :app_store_state, :app_version_state

      def initialize(version_string, app_store_state: nil, app_version_state: nil, review_detail: nil)
        @version_string = version_string
        @app_store_state = app_store_state
        @app_version_state = app_version_state
        @review_detail = review_detail
      end

      def fetch_app_store_review_detail
        raise "no review detail" unless @review_detail

        @review_detail
      end
    end

    # A Spaceship::ConnectAPI::ReviewSubmission: cancelling runs the scenario's on_cancel, which plays App Store
    # Connect's side (withdrawing the versions, or not).
    class ReviewSubmission
      attr_accessor :state

      def initialize(recorder, state, on_cancel: nil)
        @recorder = recorder
        @state = state
        @on_cancel = on_cancel
      end

      def cancel_submission
        @recorder.record(:spaceship, :cancel_submission, { state: @state })
        @state = "CANCELING"
        @on_cancel&.call(self)
      end
    end

    # A Spaceship::ConnectAPI::App with the App Store versions, edit version and review submission a scenario sets up.
    class App
      IN_PROGRESS_SUBMISSION_STATES = %w[WAITING_FOR_REVIEW IN_REVIEW UNRESOLVED_ISSUES].freeze

      attr_reader :id
      attr_accessor :versions, :edit_version, :review_submission

      def initialize(recorder)
        @recorder = recorder
        @id = "app-id"
        @versions = []
        @edit_version = EditVersion.new(recorder)
      end

      def get_app_store_versions(filter: {})
        @recorder.record(:spaceship, :get_app_store_versions, filter)
        if filter[:versionString]
          @versions.select { |version| version.version_string == filter[:versionString] }
        elsif filter[:appVersionState]
          states = filter[:appVersionState].split(",")
          @versions.select { |version| states.include?(version.app_version_state) }
        else
          @versions
        end
      end

      def get_in_progress_review_submission(platform:)
        @recorder.record(:spaceship, :get_in_progress_review_submission, { platform: platform })
        @review_submission if IN_PROGRESS_SUBMISSION_STATES.include?(@review_submission&.state)
      end

      def get_edit_app_store_version(platform:)
        @recorder.record(:spaceship, :get_edit_app_store_version, { platform: platform })
        @edit_version
      end
    end

    # A Supply::Client: records the edit it makes, and where it was created from (json_key_file resolves from there).
    class PlayClient
      attr_accessor :internal_track, :production_releases

      def initialize(recorder)
        @recorder = recorder
        @internal_track = nil
        @production_releases = []
      end

      def created_in(directory)
        @recorder.record(:supply, :make_from_config, { cwd: directory })
        self
      end

      def begin_edit(package_name:)
        @recorder.record(:supply, :begin_edit, { package_name: package_name })
      end

      def tracks(name)
        @recorder.record(:supply, :tracks, { track: name })
        [@internal_track].compact
      end

      def update_track(name, track)
        releases = track.releases.map do |release|
          { name: release.name, status: release.status, version_codes: release.version_codes }
        end
        @recorder.record(:supply, :update_track, { track: name, releases: releases })
      end

      def commit_current_edit!
        @recorder.record(:supply, :commit_current_edit!)
      end

      def client
        self
      end

      def list_application_track_releases(parent)
        @recorder.record(:supply, :list_application_track_releases, { parent: parent })
        ReleaseList.new(@production_releases)
      end
    end

    def self.release(name, state)
      Release.new(name, "RELEASE_LIFECYCLE_STATE_#{state}")
    end
  end
end
