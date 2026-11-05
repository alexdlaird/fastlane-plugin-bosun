# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

module Fastlane
  module Actions
    class BosunTestflightUploadAction < Action
      def self.run(params)
        build_number = params[:build_number]
        version = params[:version]

        begin
          other_action.upload_to_testflight(
            api_key: params[:api_key],
            ipa: params[:ipa],
            skip_submission: params[:skip_submission],
            skip_waiting_for_build_processing: false,
            wait_processing_timeout_duration: params[:wait_processing_timeout_duration],
            distribute_external: false
          )
        rescue StandardError => e
          # fastlane raises on altool's retry chatter even when the upload succeeded, so a raise is checked against App
          # Store Connect before it's trusted. A processing timeout or an outright rejection is never excused.
          raise e if params[:reraise_build_watcher] && e.message.include?("BuildWatcher exceeded")
          raise e if params[:rejection_messages].any? { |rejection| e.message.include?(rejection) }

          if params[:verify_by_version]
            raise e unless build_number && version
            raise e unless Helper::BosunHelper.build_appears?(build_number, version)

            UI.important("upload_to_testflight raised (#{e.message}), but #{version} build #{build_number} is " \
                         "present in App Store Connect — treating the upload as successful (transient altool retry " \
                         "false positive).")
          else
            raise e unless build_number
            raise e unless Helper::BosunHelper.build_appears?(build_number, nil)

            UI.important("upload_to_testflight raised (#{e.message}), but build #{build_number} is present in App " \
                         "Store Connect — treating the upload as successful (transient altool retry false positive).")
          end
        end
      end

      def self.description
        "Upload an IPA to TestFlight, telling a real failure from fastlane's false positives"
      end

      def self.details
        "Uploads with upload_to_testflight and waits for processing. When the upload raises, it re-raises a " \
          "processing timeout (reraise_build_watcher) or an outright App Store Connect rejection " \
          "(rejection_messages), and otherwise polls App Store Connect for the build: if it's there, the upload " \
          "succeeded and the error was a false positive."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_key,
                                       description: "The App Store Connect API key, as app_store_connect_api_key " \
                                                    "returns it",
                                       type: Hash,
                                       sensitive: true),
          FastlaneCore::ConfigItem.new(key: :ipa,
                                       description: "Path to the IPA, relative to the project folder",
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :build_number,
                                       description: "The IPA's build number (CFBundleVersion), to look for when the " \
                                                    "upload raises",
                                       optional: true,
                                       skip_type_validation: true),
          FastlaneCore::ConfigItem.new(key: :version,
                                       description: "The IPA's version, to look for with verify_by_version",
                                       type: String,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :skip_submission,
                                       description: "upload_to_testflight's skip_submission: upload and wait for " \
                                                    "processing, but skip distributing the build",
                                       type: Fastlane::Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :wait_processing_timeout_duration,
                                       description: "Seconds to wait for App Store Connect to process the build",
                                       type: Integer),
          FastlaneCore::ConfigItem.new(key: :reraise_build_watcher,
                                       description: "Re-raise a processing timeout instead of looking for the build",
                                       type: Fastlane::Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :rejection_messages,
                                       description: "Error messages that mean App Store Connect refused the binary, " \
                                                    "re-raised without looking for the build",
                                       type: Array,
                                       default_value: []),
          FastlaneCore::ConfigItem.new(key: :verify_by_version,
                                       description: "Look for the build of `version` (build numbers restart with " \
                                                    "each version) instead of any version's",
                                       type: Fastlane::Boolean,
                                       default_value: false)
        ]
      end

      def self.authors
        ["Alex Laird"]
      end

      def self.is_supported?(platform)
        platform == :ios
      end

      def self.example_code
        ['bosun_testflight_upload(api_key: api_key, ipa: "../build/ios/ipa/App.ipa", build_number: "42", ' \
         'version: "1.2.3", wait_processing_timeout_duration: 3600, reraise_build_watcher: true, ' \
         'rejection_messages: ["ATTRIBUTE.INVALID.DUPLICATE"], verify_by_version: true)']
      end

      def self.category
        :beta
      end
    end
  end
end
