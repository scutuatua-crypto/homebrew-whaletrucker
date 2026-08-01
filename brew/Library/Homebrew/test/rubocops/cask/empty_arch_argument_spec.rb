# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::EmptyArchArgument, :config do
  it "reports an offense when a trailing `arch` argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: ""
                            ^^^^^^^^^ Remove the empty `intel:` argument from the `arch` stanza.
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch arm: "-arm64"
      end
    CASK
  end

  it "reports an offense when a leading `arch` argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "", intel: "intel"
             ^^^^^^^ Remove the empty `arm:` argument from the `arch` stanza.
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch intel: "intel"
      end
    CASK
  end

  it "reports an offense when every `arch` argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "", intel: ""
        ^^^^^^^^^^^^^^^^^^^^^^^ Remove the `arch` stanza as all its arguments are empty.
        url "https://example.com/foo.zip"
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"
      end
    CASK
  end

  it "reports an offense when the only `arch` argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: ""
        ^^^^^^^^^^^^ Remove the `arch` stanza as all its arguments are empty.
        url "https://example.com/foo.zip"
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"
      end
    CASK
  end

  it "reports an offense without crashing when an `arch` argument key is not a literal" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", some_method => ""
                            ^^^^^^^^^^^^^^^^^ Remove the empty `some_method:` argument from the `arch` stanza.
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch arm: "-arm64"
      end
    CASK
  end

  it "reports no offenses when no `arch` argument is an empty string" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: "-intel"
      end
    CASK
  end
end
