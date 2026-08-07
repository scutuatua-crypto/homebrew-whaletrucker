class Doggo < Formula
  desc "Command-line DNS Client for Humans"
  homepage "https://doggo.mrkaran.dev/"
  url "https://github.com/mr-karan/doggo/archive/refs/tags/v1.2.1.tar.gz"
  sha256 "2328beefd30fd59cf369e6fe198a476d3cd1546b5a117971ffefd0d5fbc77b1d"
  license "GPL-3.0-or-later"
  head "https://github.com/mr-karan/doggo.git", branch: "main"

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_tahoe:   "bab4ae512ecca91209b010575814d71ce4f97ca410171ac5b2737c0ef079f1eb"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "bab4ae512ecca91209b010575814d71ce4f97ca410171ac5b2737c0ef079f1eb"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "bab4ae512ecca91209b010575814d71ce4f97ca410171ac5b2737c0ef079f1eb"
    sha256 cellar: :any_skip_relocation, sonoma:        "25fbd9b5eaf65b15e82993deba25ccc7127e03782cc9039d4a5096a58083acb2"
    sha256 cellar: :any_skip_relocation, arm64_linux:   "4d537260aab941fa6bf306775469f32d73a15a684db36706238a55333576c191"
    sha256 cellar: :any,                 x86_64_linux:  "ba1914662cc040745178a175b5c229d0a9b9ceb4390cfc36a4fa6f753747a943"
  end

  depends_on "go" => :build

  def install
    ldflags = "-X main.buildVersion=#{version} -X main.buildDate=#{time.iso8601}"
    system "go", "build", *std_go_args(ldflags:), "./cmd/doggo"

    generate_completions_from_executable(bin/"doggo", "completions")
  end

  test do
    answer = shell_output("#{bin}/doggo --short example.com NS @1.1.1.1")
    assert_equal "hera.ns.cloudflare.com.\nelliott.ns.cloudflare.com.\n", answer

    assert_match version.to_s, shell_output("#{bin}/doggo --version")
  end
end
