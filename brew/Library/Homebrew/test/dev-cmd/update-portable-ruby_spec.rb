# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-portable-ruby"

RSpec.describe Homebrew::DevCmd::UpdatePortableRuby do
  it_behaves_like "parseable arguments"
end
