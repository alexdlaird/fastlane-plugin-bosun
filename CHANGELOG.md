# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased](https://github.com/alexdlaird/fastlane-plugin-bosun/compare/1.0.0...HEAD)

### Added

- `bosun_submit_app_store` takes `replace_waiting_for_review`: when submitting, a submission still waiting for review
  is cancelled and replaced, losing its place in the queue. A submission Apple is reviewing is never touched.

## [1.0.0](https://github.com/alexdlaird/fastlane-plugin-bosun/releases/tag/1.0.0) - 2026-11-05

- First stable release of `bosun`.
