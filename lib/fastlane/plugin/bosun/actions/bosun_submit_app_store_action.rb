# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

module Fastlane
  module Actions
    class BosunSubmitAppStoreAction < Action
      def self.run(params)
        version = params[:version]
        build_number = params[:build_number]
        api_key = params[:api_key]
        push_store_assets = params[:push_store_assets]
        submit_for_review = params[:submit_for_review]
        automatic_release = params[:automatic_release]
        replace_waiting = submit_for_review && params[:replace_waiting_for_review]

        # A version already submitted, in review or live can't take another submission: fail rather than half-change
        # it. With replace_waiting_for_review, one still waiting for review is withdrawn and resubmitted instead.
        locked_states = %w[
          READY_FOR_REVIEW
          WAITING_FOR_REVIEW
          IN_REVIEW
          PROCESSING_FOR_APP_STORE
          PENDING_APPLE_RELEASE
          PENDING_DEVELOPER_RELEASE
          READY_FOR_SALE
          REPLACED_WITH_NEW_VERSION
        ]
        app_identifier = CredentialsManager::AppfileConfig.try_fetch_value(:app_identifier)
        spaceship_app = Spaceship::ConnectAPI::App.find(app_identifier)
        existing = spaceship_app.get_app_store_versions(filter: { versionString: version }).first
        replaceable_states = replace_waiting ? %w[WAITING_FOR_REVIEW] : []
        if existing && locked_states.include?(existing.app_store_state) &&
           !replaceable_states.include?(existing.app_store_state)
          UI.user_error!(
            "App Store version #{version} is in state `#{existing.app_store_state}`, so it can't be submitted " \
            "again. The TestFlight build is in; bump the version (if it shipped) or resolve the submission in App " \
            "Store Connect."
          )
        end
        waiting = Helper::BosunHelper.refuse_while_another_version_in_flight(spaceship_app, version,
                                                                             replaceable_states: replaceable_states)
        Helper::BosunHelper.withdraw_waiting_for_review(spaceship_app, waiting) unless waiting.empty?

        other_action.upload_to_app_store(
          api_key: api_key,
          app_version: version,
          build_number: build_number,
          skip_binary_upload: true,
          skip_screenshots: !push_store_assets,
          # Without this, deliver appends to existing slots instead of replacing the set, so order in App Store
          # Connect drifts from local filename order.
          overwrite_screenshots: true,
          skip_metadata: false,
          # Fresh screenshots aren't submittable until App Store Connect finishes processing them: submit separately.
          submit_for_review: submit_for_review && !push_store_assets,
          automatic_release: automatic_release,
          force: true,
          precheck_include_in_app_purchases: false,
          **listing_options(params[:listing_options])
        )
        unless submit_for_review
          # deliver attaches the build only when it submits.
          Helper::BosunHelper.attach_build(spaceship_app, version, build_number)
          UI.success("Staged App Store version #{version} (#{build_number}); submit it for review in App Store " \
                     "Connect")
          return
        end

        if push_store_assets
          Helper::BosunHelper.submit_for_review_when_assets_ready(other_action, api_key: api_key, version: version,
                                                                                build_number: build_number,
                                                                                automatic_release: automatic_release)
        end
        once_approved = automatic_release ? "it releases automatically" : "it waits for a manual release"
        UI.success("Submitted App Store version #{version} (#{build_number}) for review; once approved " \
                   "#{once_approved}")
      end

      # The listing options, built now if the lane passed a lambda, so they're read after the checks above. A lambda
      # runs from the fastlane folder, where the lane that wrote it runs, so its relative paths resolve the same.
      def self.listing_options(options)
        return options unless options.respond_to?(:call)

        Dir.chdir(FastlaneCore::FastlaneFolder.path || ".") { options.call }
      end

      def self.description
        "Stage an App Store version with a TestFlight build, or submit it for review"
      end

      def self.details
        "Refuses a version that's already submitted, in review or live, and refuses while any other version is with " \
          "App Review or awaiting release (staging then would rename that version). Then uploads the listing text " \
          "(and screenshots with `push_store_assets`) and either attaches the build, leaving the version staged, or " \
          "submits it for review (separately, once fresh screenshots finish processing). With " \
          "`replace_waiting_for_review`, a submission still waiting for review (never one in review) is cancelled " \
          "and replaced, losing its place in the review queue."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_key,
                                       description: "The App Store Connect API key, as `app_store_connect_api_key` " \
                                                    "returns it",
                                       type: Hash,
                                       sensitive: true),
          FastlaneCore::ConfigItem.new(key: :version,
                                       description: "The App Store version",
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :build_number,
                                       description: "The TestFlight build number to attach",
                                       skip_type_validation: true),
          FastlaneCore::ConfigItem.new(key: :submit_for_review,
                                       description: "Submit for review; otherwise the version is staged",
                                       type: Fastlane::Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :push_store_assets,
                                       description: "Also replace the screenshots",
                                       type: Fastlane::Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :automatic_release,
                                       description: "Release automatically once approved; otherwise it waits for " \
                                                    "\"Release this version\"",
                                       type: Fastlane::Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :replace_waiting_for_review,
                                       description: "When submitting, cancel and replace a submission still waiting " \
                                                    "for review (it loses its place in the queue); one in review " \
                                                    "is never touched",
                                       type: Fastlane::Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :listing_options,
                                       description: "Further `upload_to_app_store` options for the listing (URLs, " \
                                                    "`app_review_information`, ...), or a lambda returning them, " \
                                                    "called only once the version passes the checks",
                                       skip_type_validation: true,
                                       default_value: {})
        ]
      end

      def self.authors
        ["Alex Laird"]
      end

      def self.is_supported?(platform)
        platform == :ios
      end

      def self.example_code
        ['bosun_submit_app_store(api_key: api_key, version: "1.2.3", build_number: "42", submit_for_review: true, ' \
         "automatic_release: true)"]
      end

      def self.category
        :production
      end
    end
  end
end
