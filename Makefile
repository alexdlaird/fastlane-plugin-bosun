.PHONY: all install check test release-version

SHELL := /usr/bin/env bash

all: check test

install:
	bundle install

check: install
	bundle exec rubocop

test: install
	bundle exec rake test

release-version:
	@if [[ "${VERSION}" == "" ]]; then echo "VERSION is not set"; exit 1 ; fi
	sed -i -E "s/^( +fastlane-plugin-bosun \()[^)]+\)$$/\1${VERSION})/" Gemfile.lock
	@if [[ $$(grep -cE "^ +fastlane-plugin-bosun \(${VERSION}\)$$" Gemfile.lock) != 2 ]]; then echo "Gemfile.lock doesn't carry ${VERSION} in both of its fastlane-plugin-bosun entries"; exit 1 ; fi
