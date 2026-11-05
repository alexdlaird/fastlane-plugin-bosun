# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

require "fileutils"
require "tmpdir"
require_relative "fakes"

module Bosun
  # The outside world a scenario runs against: a project folder on disk, and fakes for every fastlane action, App
  # Store Connect, Play, the log and sleep. Both the actions and a whole Fastfile run inside it, so their effects can
  # be compared.
  class World
    APP_IDENTIFIER = "com.example.app"

    attr_reader :recorder, :app, :play_client, :project_dir
    attr_accessor :builds

    def initialize
      @recorder = Fakes::Recorder.new
      @app = Fakes::App.new(@recorder)
      @play_client = Fakes::PlayClient.new(@recorder)
      @builds = []
      @project_dir = Dir.mktmpdir("bosun")
      %w[ios/fastlane android/fastlane].each { |folder| FileUtils.mkdir_p(File.join(@project_dir, folder)) }
    end

    def cleanup
      FileUtils.rm_rf(@project_dir)
    end

    def proxy
      Fakes::ActionProxy.new(@recorder)
    end

    def path(*parts)
      File.join(@project_dir, *parts)
    end

    def write(relative_path, content)
      FileUtils.mkdir_p(File.dirname(path(relative_path)))
      File.write(path(relative_path), content)
    end

    # Runs the block with every outside call faked.
    def enter(&)
      Stubs.with(stubs, &)
    end

    private

    def stubs
      recorder = @recorder
      world = self
      original_create = FastlaneCore::Configuration.method(:create)
      [
        [CredentialsManager::AppfileConfig, :try_fetch_value, ->(_key) { APP_IDENTIFIER }],
        [Spaceship::ConnectAPI::App, :find, lambda do |identifier|
          recorder.record(:spaceship, :find_app, { identifier: identifier })
          world.app
        end],
        [Spaceship::ConnectAPI::Build, :all, lambda do |**filter|
          recorder.record(:spaceship, :builds, filter)
          world.builds.respond_to?(:call) ? world.builds.call(filter) : world.builds
        end],
        [Supply::Client, :make_from_config, ->(*) { world.play_client.created_in(Dir.pwd) }],
        [FastlaneCore::Configuration, :create, lambda do |options, values = {}|
          next original_create.call(options, values) unless values.keys == [:track]

          recorder.record(:supply, :config, values)
          values.merge(package_name: APP_IDENTIFIER)
        end],
        [Fastlane::Helper::BosunHelper, :sleep, ->(seconds) { recorder.record(:sleep, seconds) }]
      ] + %i[message important success error].map do |level|
        [FastlaneCore::UI, level, ->(text) { recorder.record(:ui, level, text) }]
      end
    end
  end

  # Swaps singleton methods for the length of a block, restoring the originals after.
  module Stubs
    def self.with(stubs, &)
      return yield if stubs.empty?

      (target, name, impl), *rest = stubs
      singleton = target.singleton_class
      original = singleton.instance_method(name) if singleton.method_defined?(name, false) ||
                                                    singleton.private_method_defined?(name, false)
      singleton.send(:define_method, name, &impl)
      begin
        with(rest, &)
      ensure
        singleton.send(:remove_method, name)
        singleton.send(:define_method, name, original) if original
      end
    end
  end
end
