# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

module Fastlane
  module Actions
    class BosunUploadToPlayInternalAction < Action
      def self.run(params)
        other_action.upload_to_play_store(
          aab: params[:aab],
          track: "internal",
          version_name: params[:version],
          skip_upload_apk: true,
          skip_upload_metadata: true,
          skip_upload_images: true,
          skip_upload_screenshots: true,
          release_status: "completed"
        )
      end

      def self.description
        "Upload an AAB to the Play Internal track"
      end

      def self.details
        "Uploads the AAB as a completed Internal release, without touching the listing."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :aab,
                                       description: "Path to the AAB, relative to the project folder",
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :version,
                                       description: "The release name",
                                       type: String,
                                       optional: true)
        ]
      end

      def self.authors
        ["Alex Laird"]
      end

      def self.is_supported?(platform)
        platform == :android
      end

      def self.example_code
        ['bosun_upload_to_play_internal(aab: "../build/app/outputs/bundle/release/app-release.aab", version: "1.2.3")']
      end

      def self.category
        :beta
      end
    end
  end
end
