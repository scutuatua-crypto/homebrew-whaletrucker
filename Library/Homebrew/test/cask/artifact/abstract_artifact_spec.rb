# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Artifact::AbstractArtifact, :cask do
  describe "#sort_order" do
    it "includes generated and platform-specific artifacts" do
      sort_order = Cask::Artifact::App.allocate.sort_order

      expect(sort_order).to include(
        Cask::Artifact::CommandWrapper,
        Cask::Artifact::GeneratedScript,
        Cask::Artifact::PreflightSteps,
        Cask::Artifact::PostflightSteps,
        Cask::Artifact::UninstallPreflightSteps,
        Cask::Artifact::UninstallPostflightSteps,
      )
      expect(sort_order.fetch(Cask::Artifact::AppImage)).to eq(sort_order.fetch(Cask::Artifact::App))
      expect(sort_order.fetch(Cask::Artifact::GeneratedCompletion))
        .to be_between(
          sort_order.fetch(Cask::Artifact::ZshCompletion),
          sort_order.fetch(Cask::Artifact::PostflightSteps),
        ).exclusive
    end
  end

  describe ".read_script_arguments" do
    let(:stanza) { :installer }

    it "accepts a string and uses it as the executable" do
      arguments = "something"

      expect(described_class.read_script_arguments(arguments, stanza)).to eq(["something", {}])
    end

    it "accepts a hash with an executable" do
      arguments = { executable: "something" }

      expect(described_class.read_script_arguments(arguments, stanza)).to eq(["something", {}])
    end

    it "does not mutate the original arguments in place" do
      arguments = { executable: "something" }
      clone = arguments.dup

      described_class.read_script_arguments(arguments, stanza)

      expect(arguments).to eq(clone)
    end
  end
end
