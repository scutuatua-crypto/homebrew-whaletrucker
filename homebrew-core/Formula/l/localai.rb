class Localai < Formula
  desc "OpenAI alternative"
  homepage "https://localai.io"
  url "https://github.com/mudler/LocalAI/archive/refs/tags/v4.8.1.tar.gz"
  sha256 "a68cdea767cbe16b9b76638ed4a6f3b200121f4a8cb7baeca5f4886a5e3d3cad"
  license "MIT"
  head "https://github.com/mudler/LocalAI.git", branch: "master"

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_tahoe:   "eecc7b4435f29fcc5936825f445ea6f5122d83320335aece8032200439208c56"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "3dac189f44a973db42e2951f9459c31732da0c91be40bb6b60f2e1a57ad64a12"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "53c684ed5b3764a307d6da6f989090337f32240af96a42626b54bbd043ebf17f"
    sha256 cellar: :any_skip_relocation, sonoma:        "a51b3aeea5ab8f003e03dc6b7e57a54f955b32a7d65ec1bbae883b377cbaa2a5"
    sha256 cellar: :any_skip_relocation, arm64_linux:   "df5dc3feeb6695b14cb589d76c4f81f222c75aa1c7f81f93d65247e939607c66"
    sha256 cellar: :any,                 x86_64_linux:  "4c5fa33dbc170d46bc28a9b8be11ada75474285fed000e26bf9665d0d919b750"
  end

  depends_on "go" => :build
  depends_on "node" => :build
  depends_on "protobuf" => :build
  depends_on "protoc-gen-go" => :build
  depends_on "protoc-gen-go-grpc" => :build

  def install
    ENV["SDKROOT"] = MacOS.sdk_path if OS.mac?

    system "make", "build", "VERSION=#{version}"
    bin.install "local-ai"
  end

  test do
    addr = "127.0.0.1:#{free_port}"

    pid = spawn bin/"local-ai", "run", "--address", addr
    sleep 5
    sleep 20 if OS.mac? && Hardware::CPU.intel?

    begin
      response = shell_output("curl -s -i #{addr}/readyz")
      assert_match "HTTP/1.1 200 OK", response
    ensure
      Process.kill("TERM", pid)
      Process.wait(pid)
    end
  end
end
