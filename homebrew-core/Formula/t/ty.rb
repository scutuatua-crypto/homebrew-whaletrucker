class Ty < Formula
  desc "Extremely fast Python type checker, written in Rust"
  homepage "https://docs.astral.sh/ty/"
  url "https://files.pythonhosted.org/packages/54/8d/d5658a08ae59f0aac8cb542a0f23c1db7072b177915e5f91f645623e2c8c/ty-0.0.68.tar.gz"
  sha256 "789b5c7d31ac188c3c0fb5c90ed10f969f9cfac67f6acbbd7e5c80f7b37ad661"
  license "MIT"
  head "https://github.com/astral-sh/ty.git", branch: "main"

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_tahoe:   "fd833fccc6d27267d9c8d5b5beb29cb5391b8c75002c736d88d0dfd2d2398696"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "dbbe17a98209e1b3c9f95f716f5d25c43d74e460574579a1fcff2e82403a6cc3"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "86b06edcd069104957f061d554b564a9443d1beed1b9c1fd4bc64fc2bea2a905"
    sha256 cellar: :any_skip_relocation, sonoma:        "ac306f2a6501ca35f9350aef0dc51b7c3dd505f0fd9bdca46bad098a7ffcb867"
    sha256 cellar: :any,                 arm64_linux:   "59303f366c76241f4dba7e286e003fb37eb02f4857a485d28ca7e7e1b28896b0"
    sha256 cellar: :any,                 x86_64_linux:  "84607a88338fbfd0d4c4a9940ad8eaf21002dbd99db3bb3d4498935497967ca3"
  end

  depends_on "rust" => :build

  def install
    ENV["TY_COMMIT_SHORT_HASH"] = tap.user
    ENV["TY_COMMIT_DATE"] = time.strftime("%F")
    system "cargo", "install", *std_cargo_args(path: "ruff/crates/ty")
    generate_completions_from_executable(bin/"ty", "generate-shell-completion")
  end

  test do
    assert_match version.major_minor_patch.to_s, shell_output("#{bin}/ty --version")

    (testpath/"bad.py").write <<~PYTHON
      def f(x: int) -> str:
          return x
    PYTHON

    output = shell_output("#{bin}/ty check #{testpath} 2>&1", 1)
    assert_match "error[invalid-return-type]: Return type does not match returned value", output
  end
end
