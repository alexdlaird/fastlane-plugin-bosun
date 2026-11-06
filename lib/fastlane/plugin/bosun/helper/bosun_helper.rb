# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

module Fastlane
  module Helper
    module BosunHelper
      module_function

      # App Store Connect lists a new build a minute or more after the upload returns, so a single check right away
      # reads "not there yet" as "not uploaded". Poll for up to ten minutes before believing the failure.
      def build_appears?(build_number, version, attempts: 20, interval: 30)
        attempts.times do |attempt|
          return true if build_uploaded?(build_number, version)

          listed = version ? "#{version} build #{build_number}" : "Build #{build_number}"
          UI.message("#{listed} not listed in App Store Connect yet (#{attempt + 1}/#{attempts}); " \
                     "checking again in #{interval}s")
          sleep(interval)
        end
        false
      end

      # Whether App Store Connect has this build: of this version when one is given (build numbers that restart with
      # each version can match an older version's build), otherwise of any version. Assumes Spaceship auth is already
      # primed (app_store_connect_api_key sets the token). Lookup errors read as "no", so a flaky verify never masks
      # the original upload failure.
      def build_uploaded?(build_number, version)
        app_identifier = CredentialsManager::AppfileConfig.try_fetch_value(:app_identifier)
        spaceship_app = Spaceship::ConnectAPI::App.find(app_identifier)
        return false unless spaceship_app

        # `version:` filters on the version (pre-release train) and `build_number:` on the Build's own `version`
        # field, which is the CFBundleVersion.
        filter = { app_id: spaceship_app.id, build_number: build_number.to_s, limit: 1 }
        filter[:version] = version.to_s if version
        !Spaceship::ConnectAPI::Build.all(**filter).empty?
      rescue StandardError => e
        UI.error("Failed to verify build #{build_number} in App Store Connect: #{e.message}")
        false
      end

      # Refuse while any version is with App Review or awaiting release, except in replaceable_states; return the
      # versions it let through, for the caller to withdraw.
      def refuse_while_another_version_in_flight(spaceship_app, version, replaceable_states: [])
        in_flight = spaceship_app.get_app_store_versions(
          filter: {
            appVersionState: %w[
              READY_FOR_REVIEW
              WAITING_FOR_REVIEW
              IN_REVIEW
              WAITING_FOR_EXPORT_COMPLIANCE
              ACCEPTED
              PENDING_APPLE_RELEASE
              PENDING_DEVELOPER_RELEASE
              PROCESSING_FOR_DISTRIBUTION
            ].join(","),
            platform: "IOS"
          }
        )
        blocking = in_flight.reject do |app_store_version|
          replaceable_states.include?(app_store_version.app_version_state)
        end
        return in_flight if blocking.empty?

        pending = blocking.map do |app_store_version|
          "#{app_store_version.version_string} (`#{app_store_version.app_version_state}`)"
        end.join(", ")
        UI.user_error!(
          "App Store version #{pending} is still with App Review or awaiting release, so #{version} can't be " \
          "staged. App Store Connect holds one version in flight, and staging now would rename that version to " \
          "#{version} and change its listing. Let it finish (or cancel it in App Store Connect), then re-run."
        )
      end

      # Cancel the review submission holding versions still waiting for review, then wait until App Store Connect
      # has released them for editing. The submission is re-read first: once Apple starts reviewing it, it's left
      # alone.
      def withdraw_waiting_for_review(spaceship_app, waiting, attempts: 20, interval: 15)
        names = waiting.map(&:version_string).join(", ")
        submission = spaceship_app.get_in_progress_review_submission(platform: "IOS")
        unless submission&.state == "WAITING_FOR_REVIEW"
          UI.user_error!(
            "App Store version #{names} was waiting for review, but its review submission is now " \
            "`#{submission&.state || 'not found'}`, so it wasn't cancelled. Check App Store Connect, then re-run."
          )
        end

        submission.cancel_submission
        UI.message("Requested cancellation of the review submission for App Store version #{names}")
        attempts.times do |attempt|
          return UI.success("Withdrew App Store version #{names} from review") if withdrawn?(spaceship_app)

          UI.message("Waiting for App Store Connect to withdraw #{names} (#{attempt + 1}/#{attempts}); " \
                     "checking again in #{interval}s")
          sleep(interval)
        end
        UI.user_error!("App Store version #{names} is still waiting for review after cancelling its submission. " \
                       "Check App Store Connect, then re-run.")
      end

      def withdrawn?(spaceship_app)
        spaceship_app.get_in_progress_review_submission(platform: "IOS").nil? &&
          spaceship_app.get_app_store_versions(filter: { appVersionState: "WAITING_FOR_REVIEW",
                                                         platform: "IOS" }).empty?
      end

      def attach_build(spaceship_app, version, build_number)
        edit_version = spaceship_app.get_edit_app_store_version(platform: "IOS")
        unless edit_version
          UI.user_error!("No editable App Store version found for #{version} after upload_to_app_store")
        end

        build = Spaceship::ConnectAPI::Build.all(app_id: spaceship_app.id, version: version,
                                                 build_number: build_number, limit: 1).first
        UI.user_error!("TestFlight build #{version} (#{build_number}) not found in App Store Connect") unless build

        edit_version.select_build(build_id: build.id)
      end

      # Submit the staged version, retrying while App Store Connect still reports freshly uploaded screenshots as
      # processing (deliver's own wait watches each asset, which finishes before the version is submittable).
      def submit_for_review_when_assets_ready(other_action, api_key:, version:, build_number:, automatic_release:,
                                              attempts: 10, delay_seconds: 30)
        attempts.times do |attempt|
          other_action.upload_to_app_store(
            api_key: api_key,
            app_version: version,
            build_number: build_number,
            skip_binary_upload: true,
            skip_metadata: true,
            skip_screenshots: true,
            submit_for_review: true,
            automatic_release: automatic_release,
            force: true,
            precheck_include_in_app_purchases: false
          )
          return
        rescue Spaceship::UnexpectedResponse => e
          raise unless e.message.include?("still in progress") && attempt < attempts - 1

          UI.important("App Store Connect is still processing screenshots (attempt #{attempt + 1}/#{attempts}); " \
                       "retrying in #{delay_seconds}s")
          sleep(delay_seconds)
        end
      end

      # Put a version code Play already holds back on the Internal track (as a draft) when a newer build has
      # replaced it there, so promoting it works for a re-run as well as a fresh release.
      def ensure_staged_on_internal(other_action, version:, version_code:)
        version_code = version_code.to_i

        staged_codes = other_action.google_play_track_version_codes(track: "internal")
        if staged_codes.include?(version_code)
          UI.message("Version code #{version_code} is already on the Internal track")
          return
        end

        UI.important("Version code #{version_code} is no longer on the Internal track (found: " \
                     "#{staged_codes.inspect}); re-staging it from Play's artifact library")
        # upload_to_play_store only writes a track when it uploads a binary in the same run, so drive its Play client
        # directly. A draft, because Play refuses a completed rollout lower than the track's current release.
        require "supply"
        Supply.config = FastlaneCore::Configuration.create(Supply::Options.available_options, { track: "internal" })
        client = Supply::Client.make_from_config
        client.begin_edit(package_name: Supply.config[:package_name])
        track = client.tracks("internal").first || AndroidPublisher::Track.new(track: "internal")
        track.releases = [
          AndroidPublisher::TrackRelease.new(name: version, status: "draft", version_codes: [version_code])
        ]
        client.update_track("internal", track)
        client.commit_current_edit!
        UI.success("Re-staged #{version} (#{version_code}) on the Internal track as a draft")
      end

      def refuse_while_production_release_in_flight(version)
        require "supply"
        Supply.config = FastlaneCore::Configuration.create(Supply::Options.available_options, { track: "production" })
        client = Supply::Client.make_from_config
        releases = client.client.list_application_track_releases(
          "applications/#{Supply.config[:package_name]}/tracks/production"
        ).releases || []
        pending = releases.select do |release|
          %w[
            RELEASE_LIFECYCLE_STATE_IN_REVIEW
            RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED
          ].include?(release.release_lifecycle_state)
        end
        return if pending.empty?

        described = pending.map do |release|
          "#{release.release_name} (`#{release.release_lifecycle_state}`)"
        end.join(", ")
        UI.user_error!(
          "Production release #{described} is still in review or awaiting publish, so #{version} can't be " \
          "submitted. Committing a Play edit now would cancel that review and resubmit everything. Let it finish " \
          "(and publish it), then re-run."
        )
      end
    end
  end
end
