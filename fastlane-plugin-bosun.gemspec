# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

require_relative "lib/fastlane/plugin/bosun/version"

Gem::Specification.new do |spec|
  spec.name = "fastlane-plugin-bosun"
  spec.version = Fastlane::Bosun::VERSION
  spec.authors = ["Alex Laird"]
  spec.email = ["contact@alexlaird.com"]
  spec.summary = "fastlane actions that safely ship apps to the App Store and Google Play"
  spec.homepage = "https://github.com/alexdlaird/fastlane-plugin-bosun"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE]
  spec.require_paths = ["lib"]
  spec.metadata["changelog_uri"] = "https://github.com/alexdlaird/fastlane-plugin-bosun/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/alexdlaird/fastlane-plugin-bosun#readme"
  spec.metadata["funding_uri"] = "https://github.com/sponsors/alexdlaird"
  spec.metadata["source_code_uri"] = "https://github.com/alexdlaird/fastlane-plugin-bosun"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "fastlane", ">= 2.236.1"
end
