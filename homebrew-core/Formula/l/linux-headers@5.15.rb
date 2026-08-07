class LinuxHeadersAT515 < Formula
  desc "Header files of the Linux kernel"
  homepage "https://kernel.org/"
  url "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.15.214.tar.gz"
  sha256 "a0369a616116889fe061f5db546739287bc723cd4bd868dc41e59f911cdd5f17"
  license "GPL-2.0-only" => { with: "Linux-syscall-note" }
  compatibility_version 1

  livecheck do
    url :homepage
    regex(/href=.*?linux[._-]v?(5\.15(?:\.\d+)*)\.t/i)
  end

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_linux:  "6432f56c254cb320e510e9d719c104d6da8ad641f16411b99c066a1f71471d2d"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "8a2c324b51d330a16e27a3b3606f6f099fd49ab19abf4f64e91cdcbaa4cb19f3"
  end

  keg_only :versioned_formula

  depends_on :linux

  def install
    system "make", "headers"

    cd "usr/include" do
      Pathname.glob("**/*.h").each do |header|
        (include/header.dirname).install header
      end
    end
  end

  test do
    assert_match "KERNEL_VERSION", (include/"linux/version.h").read
  end
end
