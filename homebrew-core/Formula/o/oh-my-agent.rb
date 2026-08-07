class OhMyAgent < Formula
  desc "Portable multi-agent harness for .agents-based skills and workflows"
  homepage "https://firstfluke.com/oh-my-agent/"
  url "https://registry.npmjs.org/oh-my-agent/-/oh-my-agent-11.8.0.tgz"
  sha256 "be3df8e831a6353deef989b0231a5e88d807c63b76db288c713269b3dcfaec31"
  license "MIT"

  bottle do
    sha256 cellar: :any, arm64_tahoe:   "4de3e1616d278fa3b0bece003bda930640e9cd53c7644c5a8c6c675c81bd17ce"
    sha256 cellar: :any, arm64_sequoia: "7476f0eea6042ade172c219e42c50ecf7998d284c1a5fad42519f571ed4a8095"
    sha256 cellar: :any, arm64_sonoma:  "8054ce3f89e0f7b368cd5008579ec24ec8a2bc0547e28836d2aec43dc5e0e3ae"
    sha256 cellar: :any, sonoma:        "1d419f94930863d3da0c83a73e2da56498874fc35b37ddb303c0d290cd1abe81"
    sha256 cellar: :any, arm64_linux:   "89e7cdca2d3bfbd060584c8cb24b446ea42c00c80c1fa4e0333f85ec26ecd568"
    sha256 cellar: :any, x86_64_linux:  "f3ccb52bc4ccd63e0311a1c7ce686a79318a0d4dc84f540e6ea46d07fd9a5290"
  end

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args

    node_modules = libexec/"lib/node_modules/oh-my-agent/node_modules"
    # Remove incompatible pre-built `bare-fs`/`bare-os`/`bare-path`/`bare-url` binaries
    os = OS.kernel_name.downcase
    arch = Hardware::CPU.intel? ? "x64" : Hardware::CPU.arch.to_s
    node_modules.glob("{bare-fs,bare-os,bare-path,bare-url}/prebuilds/*")
                .each { |dir| rm_r(dir) if dir.basename.to_s != "#{os}-#{arch}" }

    rm_r(node_modules.glob("better-sqlite3/prebuilds/*"))
    cd(node_modules/"better-sqlite3") { system "npm", "run", "build-release" }

    bin.install_symlink Dir[libexec/"bin/*"]
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/oh-my-agent --version")

    output = JSON.parse(shell_output("#{bin}/oh-my-agent memory:init --json"))
    assert_empty output["updated"]
    assert_path_exists testpath/".agents/state/memories/orchestrator-session.md"
    assert_path_exists testpath/".agents/state/memories/task-board.md"
  end
end
