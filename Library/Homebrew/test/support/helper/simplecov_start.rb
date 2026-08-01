# typed: strict
# frozen_string_literal: true

require "rubygems/version"

simplecov_root = File.expand_path("../../..", __dir__)
Dir.chdir(simplecov_root) { require "simplecov" }

SimpleCov.start
