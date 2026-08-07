class Infracost < Formula
  desc "Cost estimates for Terraform, Terragrunt, and CloudFormation"
  homepage "https://www.infracost.io/docs/"
  url "https://github.com/infracost/cli/archive/refs/tags/v2.16.0.tar.gz"
  sha256 "514aa0c65a869e4dcc483f5070e6c49dbbccdbd7e71485f0ec3a562bb1b3fd60"
  license "Apache-2.0"
  head "https://github.com/infracost/cli.git", branch: "main"

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_tahoe:   "3674074527ea63fe3fcc39f77b2bf2b38a70af3b79f5143ec639d224f83a8e28"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "3674074527ea63fe3fcc39f77b2bf2b38a70af3b79f5143ec639d224f83a8e28"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "3674074527ea63fe3fcc39f77b2bf2b38a70af3b79f5143ec639d224f83a8e28"
    sha256 cellar: :any_skip_relocation, sonoma:        "44ae90678706e932aebe58839456ce77e2a8c2c6fcc6940712b644159ad6e40e"
    sha256 cellar: :any_skip_relocation, arm64_linux:   "ce6134f555d1375eebaf875641e74b7d260a612a8efa6116295cf912a2c873a5"
    sha256 cellar: :any_skip_relocation, x86_64_linux:  "d38c9edc96c4e7b7497f3a34460f821465ce0f2aad87acd3b7113b67ac60f744"
  end

  depends_on "go" => :build

  def install
    ENV["CGO_ENABLED"] = "0"
    ldflags = "-X github.com/infracost/cli/version.Version=v#{version}"
    system "go", "build", *std_go_args(output: bin/"infracost", ldflags:), "main.go"

    generate_completions_from_executable(bin/"infracost", "completion")
  end

  test do
    assert_match "v#{version}", shell_output("#{bin}/infracost --version 2>&1")

    ENV["INFRACOST_CLI_AUTHENTICATION_TOKEN"] = "dummy"
    output = shell_output("#{bin}/infracost setup --no-color 2>&1", 1)
    assert_match "setup requires interactive login", output
  end
end
