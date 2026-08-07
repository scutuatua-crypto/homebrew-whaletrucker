class Zot < Formula
  desc "Lightweight coding agent harness written in Go"
  homepage "https://www.zot.sh/"
  url "https://github.com/patriceckhart/zot/archive/refs/tags/v0.3.37.tar.gz"
  sha256 "666b7415495e0219cc851572eee560d09f1dbeeaa062cb2265d513a095ad3dea"
  license "MIT"
  head "https://github.com/patriceckhart/zot.git", branch: "main"

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_tahoe:   "ef9158a497e84f90da605384f1bd370e8dc5a4819a066e5e5447ee2b81118cdd"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "ef9158a497e84f90da605384f1bd370e8dc5a4819a066e5e5447ee2b81118cdd"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "ef9158a497e84f90da605384f1bd370e8dc5a4819a066e5e5447ee2b81118cdd"
    sha256 cellar: :any_skip_relocation, sonoma:        "9e77a9dad0fc89c7e1b2e53b479126384d4fc961ad859b2b29368619fe21e3e2"
    sha256 cellar: :any_skip_relocation, arm64_linux:   "2e6c8c67c3cd771f7cc2478ad20339197d1e267467de2d31e72a6dedf5348247"
    sha256 cellar: :any,                 x86_64_linux:  "c3866116afd7663786ff3f319ccd2aeebf09d9b0e50c5fbf26d42325f1f6f447"
  end

  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args(ldflags: "-X main.version=#{version}"), "./cmd/zot"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/zot --version")
    assert_match "zot: no credential for anthropic", shell_output("#{bin}/zot rpc 2>&1", 1)
  end
end
