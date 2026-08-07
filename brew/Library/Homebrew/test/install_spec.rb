# typed: strict
# frozen_string_literal: true

require "cask/installer"
require "install"
require "dependency"
require "test/support/fixtures/testball"

RSpec.describe Homebrew::Install do
  specify "::perform_preinstall_checks runs non-fatal preinstall diagnostics" do
    allow(described_class).to receive(:check_prefix)
    allow(described_class).to receive(:check_cpu)
    allow(described_class).to receive(:attempt_directory_creation)

    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:supported_configuration_checks, fatal: false)
      .ordered
    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:preinstall_checks, fatal: false)
      .ordered
    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:fatal_preinstall_checks)
      .ordered

    described_class.perform_preinstall_checks
  end

  describe "::fetch_formulae" do
    it "skips formulae whose fetch steps raise and continues with the rest" do
      good_fi = FormulaInstaller.new(formula("good-bottle") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end)
      bad_fi = FormulaInstaller.new(formula("bad-bottle") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end)
      [good_fi, bad_fi].each do |fi|
        allow(fi).to receive(:prelude_fetch)
        allow(fi).to receive(:prelude)
      end
      allow(good_fi).to receive(:enqueue_fetch)
      allow(bad_fi).to receive(:enqueue_fetch).and_raise("unexpected failure")

      expect do
        expect(described_class.fetch_formulae([good_fi, bad_fi])).to eq([good_fi])
      end.to output(/Error: bad-bottle: unexpected failure/).to_stderr
    end
  end

  describe "::enqueue_cask_installers" do
    it "skips casks whose enqueue raises and continues with the rest" do
      bad_cask = instance_double(Cask::Cask, to_s: "bad-cask")
      bad_installer = instance_double(Cask::Installer, cask:                                bad_cask,
                                                       source_download_requires_pre_fetch?: false)
      allow(bad_installer).to receive(:enqueue_downloads)
        .and_raise(URI::InvalidURIError, 'bad URI (is not URI?): "https://example.com/bad -cask.dmg"')
      good_installer = instance_double(Cask::Installer, source_download_requires_pre_fetch?: false)
      expect(good_installer).to receive(:enqueue_downloads)

      download_queue = Homebrew::DownloadQueue.new(pour: true)
      begin
        expect { described_class.enqueue_cask_installers([bad_installer, good_installer], download_queue:) }
          .to output(/Error: bad-cask: bad URI/).to_stderr
      ensure
        download_queue.shutdown
      end
    end
  end

  describe "::print_dry_run_dependencies" do
    it "splits fresh installs and upgrades under separate headers" do
      fresh = formula("fresh-dep") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      installed = formula("installed-dep") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      allow(fresh).to receive(:any_version_installed?).and_return(false)
      allow(installed).to receive(:any_version_installed?).and_return(true)
      deps = [
        instance_double(Dependency, to_formula: fresh),
        instance_double(Dependency, to_formula: installed),
      ]

      expect { described_class.print_dry_run_dependencies(Testball.new, deps, &:name) }
        .to output(/Would install 1 dependency.*fresh-dep.*Would upgrade 1 dependency.*installed-dep/m).to_stdout
    end
  end
end
