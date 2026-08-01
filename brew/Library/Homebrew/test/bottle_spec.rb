# typed: strict
# frozen_string_literal: true

require "bottle_specification"
require "test/support/fixtures/testball_bottle"

RSpec.describe Bottle do
  describe "#filename" do
    it "renders the bottle filename" do
      bottle_spec = BottleSpecification.new
      bottle_spec.sha256(arm64_big_sur: "deadbeef" * 8)
      tag = Utils::Bottles::Tag.from_symbol :arm64_big_sur
      bottle = described_class.new(TestballBottle.new, bottle_spec, tag)

      expect(bottle.filename.to_s).to eq("testball_bottle--0.1.arm64_big_sur.bottle.tar.gz")
    end
  end

  describe "#downloaded_and_valid?" do
    it "trusts cached immutable GitHub Packages bottle blobs matching the expected checksum" do
      tag = Utils::Bottles::Tag.from_symbol(:arm64_big_sur)
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      bottle_spec.sha256(
        cellar:        :any_skip_relocation,
        arm64_big_sur: "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97",
      )
      bottle = described_class.new(nil, bottle_spec, tag,
                                   name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))

      bottle.cached_download.dirname.mkpath
      bottle.cached_download.write("cached")

      expect(bottle.resource).not_to receive(:verify_download_integrity)

      expect(bottle.downloaded_and_valid?).to be true
    end
  end

  describe "#github_packages_manifest_resource" do
    sig { returns(String) }
    def bottle_domain = "https://mirror.example.com/homebrew-bottles"

    sig { params(root_url: String).returns(Bottle) }
    def test_bottle(root_url = bottle_domain)
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(root_url)
      bottle_spec.sha256(
        cellar:            :any_skip_relocation,
        Utils::Bottles.tag.to_sym => "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97",
      )
      described_class.new(nil, bottle_spec, Utils::Bottles.tag,
                          name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))
    end

    before do
      ENV["HOMEBREW_BOTTLE_DOMAIN"] = bottle_domain
    end

    it "falls back to GHCR for a custom bottle domain" do
      bottle = test_bottle
      manifest_resource = bottle.github_packages_manifest_resource
      downloader = manifest_resource&.downloader
      raise "Expected a GitHub Packages download strategy" unless downloader.is_a?(CurlGitHubPackagesDownloadStrategy)

      expect([manifest_resource&.url, downloader.mirrors]).to eq([
        "#{bottle_domain}/foo/manifests/1.2.3",
        ["#{HOMEBREW_BOTTLE_DEFAULT_DOMAIN}/foo/manifests/1.2.3"],
      ])
    end

    it "keeps the bottle mirror when neither manifest URL is available", :aggregate_failures do
      bottle = test_bottle
      manifest_resource = bottle.github_packages_manifest_resource
      raise "Expected a bottle manifest resource" if manifest_resource.nil?

      allow(manifest_resource).to receive(:fetch)
        .and_raise(DownloadError.new(manifest_resource, RuntimeError.new("manifest missing")))

      expect { bottle.fetch_tab }.to raise_error(DownloadError)
      expect(bottle.url).to start_with(bottle_domain)
    end

    it "does not create a manifest resource for an unrelated flat bottle domain" do
      bottle = test_bottle("https://example.com/bottles")

      expect(bottle.github_packages_manifest_resource).to be_nil
    end
  end

  describe "#sbom_supplement" do
    it "reads the supplement from a valid bottle manifest" do
      bottle_spec = BottleSpecification.new
      bottle_spec.sha256(arm64_big_sur: "deadbeef" * 8)
      bottle = described_class.new(nil, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_big_sur),
                                   name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))
      supplement = { "packages" => [{ "SPDXID" => "SPDXRef-Compiler" }] }
      manifest_resource = instance_double(
        Resource::BottleManifest,
        downloaded_and_valid?: true,
        sbom_supplement:       supplement,
      )

      allow(bottle).to receive(:github_packages_manifest_resource).and_return(manifest_resource)

      expect(bottle.sbom_supplement).to eq(supplement)
    end
  end
end
