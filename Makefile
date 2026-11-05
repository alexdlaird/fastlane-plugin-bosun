.PHONY: all install check test

SHELL := /usr/bin/env bash

all: check test

install:
	bundle install

check: install
	bundle exec rubocop

test: install
	bundle exec rake test
