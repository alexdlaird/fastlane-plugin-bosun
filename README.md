# bosun

[![Version](https://img.shields.io/github/v/release/alexdlaird/fastlane-plugin-bosun)](https://github.com/alexdlaird/fastlane-plugin-bosun/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/alexdlaird/fastlane-plugin-bosun/build.yml)](https://github.com/alexdlaird/fastlane-plugin-bosun/actions/workflows/build.yml)
[![GitHub License](https://img.shields.io/github/license/alexdlaird/fastlane-plugin-bosun)](https://github.com/alexdlaird/fastlane-plugin-bosun/blob/main/LICENSE)

`bosun` is a `fastlane` plugin that safely ships apps to the App Store and Google Play. Its actions upload builds to
TestFlight and Play's Internal track and confirm they landed, even when `fastlane` reports a false failure, then stage or
submit App Store and Play Production releases with any submission already in review kept intact. The same lanes work for
every app you ship.

## Installation

`bosun` is installed from GitHub, pinned to its major version. Add it to `fastlane/Pluginfile`:

```ruby
gem "fastlane-plugin-bosun", git: "https://github.com/alexdlaird/fastlane-plugin-bosun", tag: "v1"
```

Then run `bundle install`. `v1` moves to each `1.x.y` release, so `bundle update fastlane-plugin-bosun` picks up fixes
without changing your Pluginfile. Pin a full version, like `tag: "1.0.0"`, to opt out.

## Basic Usage

Each action takes the App Store Connect API key the lane creates, so `fastlane`'s other App Store Connect calls share
it.

### TestFlight

```ruby
lane :deploy_testflight do |options|
  api_key = app_store_connect_api_key(
    key_id: ENV["APP_STORE_CONNECT_API_KEY_ID"],
    issuer_id: ENV["APP_STORE_CONNECT_API_ISSUER_ID"],
    key_filepath: File.expand_path("~/.appstoreconnect/private_keys/AuthKey_#{ENV['APP_STORE_CONNECT_API_KEY_ID']}.p8")
  )
  build_number = bosun_next_build_number(api_key: api_key, version: options[:version], scope_to_version: true)

  # ... build the IPA with build_number ...

  bosun_testflight_upload(
    api_key: api_key,
    ipa: "../build/ios/ipa/App.ipa",
    build_number: build_number,
    version: options[:version],
    wait_processing_timeout_duration: 3600,
    reraise_build_watcher: true,
    rejection_messages: ["bundle version must be higher", "ATTRIBUTE.INVALID.DUPLICATE"],
    verify_by_version: true
  )
end
```

When the upload raises, `bosun_testflight_upload` re-raises a processing timeout or an outright rejection, and
otherwise polls App Store Connect for the build: if it's there, the upload succeeded.

### App Store

```ruby
lane :submit_appstore do |options|
  bosun_submit_app_store(
    api_key: api_key,
    version: options[:version],
    build_number: options[:build_number],
    submit_for_review: options[:submit_for_review].to_s == "true",
    automatic_release: true
  )
end
```

Without `submit_for_review`, the version is staged with the build attached, ready to submit from App Store Connect.
Either way, a version already submitted, in review or live is refused, and so is any change while another version is
with App Review or awaiting release: App Store Connect holds one version in flight, and staging then would rename it.
When submitting with `replace_waiting_for_review`, a submission still waiting for review is cancelled and replaced
instead, losing its place in the queue; one Apple is reviewing is never touched.

### Google Play

```ruby
lane :submit_production do |options|
  bosun_submit_play_production(
    version: options[:version],
    version_code: options[:version_code],
    metadata_dir: File.expand_path("metadata/android"),
    submit_for_review: options[:submit_for_review].to_s == "true"
  )
end
```

The Internal-track build is promoted to Production as a draft, or submitted for review. Submitting is refused while a
Production release is in review or approved but unpublished; with `replace_in_review`, Play cancels that review and
reviews the new release instead.

## Documentation

Each action's options are documented in its source and by `fastlane action <name>`. For complete lanes built from them,
see the [iOS](https://github.com/HeliumEdu/frontend/blob/main/ios/fastlane/Fastfile) and
[Android](https://github.com/HeliumEdu/frontend/blob/main/android/fastlane/Fastfile) Fastfiles of
[Helium](https://github.com/HeliumEdu/frontend), which ship with them.

| Action | Does |
|---|---|
| [`bosun_next_build_number`](https://github.com/alexdlaird/fastlane-plugin-bosun/blob/main/lib/fastlane/plugin/bosun/actions/bosun_next_build_number_action.rb) | Get the next TestFlight build number, for a version or across versions |
| [`bosun_testflight_upload`](https://github.com/alexdlaird/fastlane-plugin-bosun/blob/main/lib/fastlane/plugin/bosun/actions/bosun_testflight_upload_action.rb) | Upload an IPA to TestFlight, telling a real failure from a false positive |
| [`bosun_submit_app_store`](https://github.com/alexdlaird/fastlane-plugin-bosun/blob/main/lib/fastlane/plugin/bosun/actions/bosun_submit_app_store_action.rb) | Stage an App Store version with its build, or submit it for review |
| [`bosun_next_version_code`](https://github.com/alexdlaird/fastlane-plugin-bosun/blob/main/lib/fastlane/plugin/bosun/actions/bosun_next_version_code_action.rb) | Get the next Play version code, across every track |
| [`bosun_upload_to_play_internal`](https://github.com/alexdlaird/fastlane-plugin-bosun/blob/main/lib/fastlane/plugin/bosun/actions/bosun_upload_to_play_internal_action.rb) | Upload an AAB to the Internal track |
| [`bosun_submit_play_production`](https://github.com/alexdlaird/fastlane-plugin-bosun/blob/main/lib/fastlane/plugin/bosun/actions/bosun_submit_play_production_action.rb) | Promote an Internal build to Production, as a draft or submitted for review |

## Contributing

If you would like to get involved, be sure to review
the [Contribution Guide](https://github.com/alexdlaird/fastlane-plugin-bosun/blob/main/CONTRIBUTING.md).

Want to contribute financially? If you've found `bosun` useful, [sponsorship](https://github.com/sponsors/alexdlaird)
would also be greatly appreciated!
