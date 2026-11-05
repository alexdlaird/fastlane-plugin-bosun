# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

module Fastlane
  module Actions
    class BosunNextVersionCodeAction < Action
      def self.run(_params)
        codes = %w[production beta alpha internal].flat_map do |track|
          other_action.google_play_track_version_codes(track: track)
        rescue StandardError => e
          # A track with no releases raises rather than returning empty.
          UI.message("No version codes on track '#{track}' (#{e.class})")
          []
        end

        next_code = (codes.flatten.map(&:to_i).max || 0) + 1
        UI.message("Next version code: #{next_code}")
        next_code
      end

      def self.description
        "The next Play version code, taken across every track"
      end

      def self.details
        "Takes the highest version code on the production, beta, alpha and internal tracks, plus one. Logs " \
          "`Next version code: <n>` and returns the number."
      end

      def self.available_options
        []
      end

      def self.return_value
        "The next version code"
      end

      def self.return_type
        :int
      end

      def self.authors
        ["Alex Laird"]
      end

      def self.is_supported?(platform)
        platform == :android
      end

      def self.example_code
        ["bosun_next_version_code"]
      end

      def self.category
        :production
      end
    end
  end
end
