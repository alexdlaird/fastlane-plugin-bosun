# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

module Fastlane
  module Actions
    class BosunNextBuildNumberAction < Action
      def self.run(params)
        version = params[:version]

        current = if params[:scope_to_version]
                    other_action.latest_testflight_build_number(
                      api_key: params[:api_key],
                      version: version,
                      initial_build_number: 0
                    )
                  else
                    other_action.latest_testflight_build_number(
                      api_key: params[:api_key],
                      initial_build_number: 0
                    )
                  end

        next_number = current + 1
        next_number = [next_number, params[:floor].to_i].max unless params[:floor].nil?
        UI.message(version ? "Next build number for #{version}: #{next_number}" : "Next build number: #{next_number}")
        next_number
      end

      def self.description
        "The next TestFlight build number: App Store Connect's latest plus one"
      end

      def self.details
        "Looks up the latest TestFlight build number, for the given version or across every version, adds one, and " \
          "raises it to `floor` if that's higher. Logs `Next build number for <version>: <n>` (or " \
          "`Next build number: <n>` without a version) and returns the number."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_key,
                                       description: "The App Store Connect API key, as app_store_connect_api_key " \
                                                    "returns it",
                                       type: Hash,
                                       sensitive: true),
          FastlaneCore::ConfigItem.new(key: :version,
                                       description: "The version (named in the log line, and the lookup's scope " \
                                                    "with scope_to_version)",
                                       type: String,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :scope_to_version,
                                       description: "Look up the latest build of `version` only, rather than of " \
                                                    "every version",
                                       type: Fastlane::Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :floor,
                                       description: "A minimum for the next number (e.g. a CI run number)",
                                       optional: true,
                                       skip_type_validation: true)
        ]
      end

      def self.return_value
        "The next build number"
      end

      def self.return_type
        :int
      end

      def self.authors
        ["Alex Laird"]
      end

      def self.is_supported?(platform)
        platform == :ios
      end

      def self.example_code
        ['bosun_next_build_number(api_key: api_key, version: "1.2.3", scope_to_version: true)']
      end

      def self.category
        :beta
      end
    end
  end
end
