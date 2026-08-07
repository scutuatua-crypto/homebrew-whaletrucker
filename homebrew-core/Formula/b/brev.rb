class Brev < Formula
  desc "CLI tool for managing workspaces provided by brev.dev"
  homepage "https://developer.nvidia.com/brev"
  url "https://github.com/brevdev/brev-cli/archive/refs/tags/v0.6.333.tar.gz"
  sha256 "20375bbff0c36d0a655f48a558a8895980368143f412d1bb31b5c23667f0dacb"
  license "MIT"
  head "https://github.com/brevdev/brev-cli.git", branch: "main"

  # Upstream appears to use GitHub releases to indicate that a version is
  # released (and some tagged versions don't end up as a release), so it's
  # necessary to check release versions instead of tags.
  livecheck do
    url :stable
    strategy :github_latest
  end

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_tahoe:   "cdae7c50ef51d6d1ef85b7e2ef18a3f77afbd6c62c9004557edf4e20c05a8a9f"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "cdae7c50ef51d6d1ef85b7e2ef18a3f77afbd6c62c9004557edf4e20c05a8a9f"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "cdae7c50ef51d6d1ef85b7e2ef18a3f77afbd6c62c9004557edf4e20c05a8a9f"
    sha256 cellar: :any_skip_relocation, sonoma:        "46e5917316598ea641ed9f7617e18deedb4cddd3eff67208450f12975a54f2f3"
    sha256 cellar: :any,                 arm64_linux:   "5bcb970e55db8012c7120f2067899a31b8e76bd58834baaa1d53f672bbf9a030"
    sha256 cellar: :any,                 x86_64_linux:  "5ed29970fe7b5515b199e92357daadeb94eb040aed42587d51349c12176552b7"
  end

  depends_on "go" => :build

  def install
    ENV["CGO_ENABLED"] = "1" if OS.linux? && Hardware::CPU.arm?

    ldflags = "-X github.com/brevdev/brev-cli/pkg/cmd/version.Version=v#{version}"
    system "go", "build", *std_go_args(ldflags:)

    generate_completions_from_executable(bin/"brev", shell_parameter_format: :cobra)
  end

  test do
    system bin/"brev", "healthcheck"
  end
end
