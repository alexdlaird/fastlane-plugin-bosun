# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

require "fastlane/plugin/bosun/version"

module Fastlane
  module Bosun
    def self.all_classes
      Dir[File.expand_path("**/{actions,helper}/*.rb", File.dirname(__FILE__))]
    end
  end
end

Fastlane::Bosun.all_classes.each do |current|
  require current
end
