# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

module Fastlane
  module Actions
    class BosunSubmitPlayProductionAction < Action
      def self.run(params)
        version = params[:version]
        version_code = params[:version_code]
        metadata_dir = params[:metadata_dir]
        submit_for_review = params[:submit_for_review]
        push_store_assets = params[:push_store_assets]

        # Play wants changelogs/<versionCode>.txt for every release: stamped from the one template.
        template = File.join(metadata_dir, "en-US/default_release_notes.txt")
        changelog_dir = File.join(metadata_dir, "en-US/changelogs")
        UI.user_error!("Missing #{template}") unless File.exist?(template)
        FileUtils.mkdir_p(changelog_dir)
        FileUtils.cp(template, File.join(changelog_dir, "#{version_code}.txt"))

        if submit_for_review && !params[:replace_in_review]
          Helper::BosunHelper.refuse_while_production_release_in_flight(version)
        end
        Helper::BosunHelper.ensure_staged_on_internal(other_action, version: version, version_code: version_code)

        # Promotion happens only on a run that uploads no binary of its own, so both skip flags matter.
        other_action.upload_to_play_store(
          metadata_path: metadata_dir,
          track: "internal",
          track_promote_to: "production",
          version_code: version_code,
          # Completed = sent for review (Play reviews automatically); Managed Publishing then holds it for publish. A
          # draft waits for "Send for review" in Play Console.
          track_promote_release_status: submit_for_review ? "completed" : "draft",
          skip_upload_apk: true,
          skip_upload_aab: true,
          skip_upload_metadata: false,
          skip_upload_images: !push_store_assets,
          skip_upload_screenshots: !push_store_assets
        )
        if submit_for_review
          UI.success("Submitted #{version} (#{version_code}) to Production for review; once approved Play holds it " \
                     "for a manual Publish")
        else
          UI.success("Staged #{version} (#{version_code}) on Production as a draft; send it for review in Play " \
                     "Console")
        end
      end

      def self.description
        "Promote an Internal-track build to Play Production, as a draft or submitted for review"
      end

      def self.details
        "Stamps `changelogs/<version_code>.txt` from `en-US/default_release_notes.txt`, puts the version code " \
          "back on the Internal track if a newer build replaced it there, and promotes it to Production with the " \
          "listing text (and images and screenshots with `push_store_assets`). Submitting refuses while a " \
          "Production release is in review or approved but unpublished, unless `replace_in_review`: committing " \
          "then makes Play cancel that review and review the new release instead."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :version,
                                       description: "The release's version",
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :version_code,
                                       description: "The Internal-track version code to promote",
                                       skip_type_validation: true),
          FastlaneCore::ConfigItem.new(key: :metadata_dir,
                                       description: "Absolute path to the Play metadata folder " \
                                                    "(`fastlane/metadata/android`)",
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :submit_for_review,
                                       description: "Send the release for review; otherwise it's a Production draft",
                                       type: Fastlane::Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :push_store_assets,
                                       description: "Also replace the listing images and screenshots",
                                       type: Fastlane::Boolean,
                                       default_value: false),
          FastlaneCore::ConfigItem.new(key: :replace_in_review,
                                       description: "Submit even while a Production release is in review or " \
                                                    "awaiting publish, so Play cancels that review and reviews this " \
                                                    "one",
                                       type: Fastlane::Boolean,
                                       default_value: false)
        ]
      end

      def self.authors
        ["Alex Laird"]
      end

      def self.is_supported?(platform)
        platform == :android
      end

      def self.example_code
        ['bosun_submit_play_production(version: "1.2.3", version_code: "42", ' \
         'metadata_dir: File.expand_path("metadata/android"), submit_for_review: true)']
      end

      def self.category
        :production
      end
    end
  end
end
