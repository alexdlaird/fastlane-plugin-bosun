# frozen_string_literal: true

# Copyright (c) 2026 Alex Laird
#
# SPDX-License-Identifier: MIT

module Bosun
  # Runs a Fastfile's lanes inside a World the way fastlane does: lane bodies from the fastlane folder, actions from
  # the project folder. bosun actions run for real; every other action is recorded by the World.
  class FastfileSandbox
    UI = Fastlane::UI

    def initialize(world, fastfile_path)
      @world = world
      @path = fastfile_path
      @lanes = {}
      instance_eval(File.read(fastfile_path), fastfile_path)
    end

    def run(name, options = {})
      @world.enter { Dir.chdir(File.dirname(@path)) { call_lane(name, options) } }
    end

    def default_platform(_platform); end

    def platform(_platform, &)
      instance_eval(&)
    end

    def desc(_text); end

    def lane(name, &block)
      @lanes[name] = block
    end

    def private_lane(name, &block)
      @lanes[name] = block
    end

    def sleep(seconds)
      @world.recorder.record(:sleep, seconds)
    end

    def method_missing(name, *args, **kwargs)
      options = kwargs.empty? ? args.first : kwargs
      return call_lane(name, options || {}) if @lanes.key?(name)
      return run_bosun_action(name, options || {}) if name.to_s.start_with?("bosun_")

      @world.recorder.action(name, options)
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end

    private

    def call_lane(name, options)
      instance_exec(options, &@lanes[name])
    end

    def run_bosun_action(name, values)
      action = Fastlane::Actions.const_get("#{name.to_s.split('_').map(&:capitalize).join}Action")
      config = FastlaneCore::Configuration.create(action.available_options, values)
      proxy = @world.proxy
      Stubs.with([[action, :other_action, -> { proxy }]]) { Dir.chdir("..") { action.run(config) } }
    end
  end
end
