class Circleci < Formula
  desc "Official command-line tool for CircleCI"
  homepage "https://cli.circleci.com"
  # Updates should be pushed no more frequently than once per week.
  url "https://github.com/CircleCI-Public/circleci-cli.git",
      tag:      "v1.0.47264",
      revision: "b054109b40de028c06730e7134a7a869f0382495"
  license "MIT"
  head "https://github.com/CircleCI-Public/circleci-cli.git", branch: "main"

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_tahoe:   "94e6686ca11d676797f7e9e18d2905f8f5a291a2c33dff9a72806864a347155a"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "1b38a1108cbe4b2309768b599cfefeaedfe6b6c004855da6dcc98582aa258380"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "67688e69edc1494d8cb5aaef02c3ea327bb3b238ce5830015f5173c7db826055"
    sha256 cellar: :any_skip_relocation, sonoma:        "d82c5698309e2be475ea5fb04d0117f26970d140c8f67267aef68c4185ef3b17"
    sha256 cellar: :any_skip_relocation, arm64_linux:   "bf1b41d150fc32930a7cdb7bb73db167d1e43947e2e509d68a2b19c8a295e714"
    sha256 cellar: :any,                 x86_64_linux:  "d5e423340121c68d8d6de519afb1507efb5df16a85a06fd490f69beb125b44db"
  end

  depends_on "go" => :build

  def install
    ldflags = "-X main.version=#{version}"
    system "go", "build", *std_go_args(ldflags:), "./cmd/circleci"

    generate_completions_from_executable(bin/"circleci", "completion")
    system bin/"circleci", "man", "--output", man1/"circleci.1"
  end

  test do
    ENV["DO_NOT_TRACK"] = "1"
    # assert basic script execution
    assert_match(/^circleci #{version} \(\h{12}\)$/, shell_output("#{bin}/circleci version").strip)
    (testpath/".circleci.yml").write("{version: 2.1}")
    output = shell_output("#{bin}/circleci config pack #{testpath}/.circleci.yml")
    assert_match "version: 2.1", output
  end
end
