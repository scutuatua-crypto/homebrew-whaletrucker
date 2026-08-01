# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/unlink"

RSpec.describe Homebrew::Cmd::UnlinkCmd do
  it_behaves_like "parseable arguments"

  it "unlinks a Formula", :integration_test do
    setup_test_formula "testball", tab_attributes: { installed_on_request: true }
    formula_prefix = Formula["testball"].prefix
    (formula_prefix/"bin").mkpath
    (formula_prefix/"bin/test").write "test"
    (HOMEBREW_PREFIX/"bin").mkpath
    (HOMEBREW_PREFIX/"bin/test").make_relative_symlink(formula_prefix/"bin/test")
    HOMEBREW_LINKED_KEGS.mkpath
    (HOMEBREW_LINKED_KEGS/"testball").make_relative_symlink(formula_prefix)

    expect { brew "unlink", "testball" }
      .to output(/Unlinking /).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
