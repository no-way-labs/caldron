class Mitt < Formula
  desc "Encrypted file transfer CLI tool"
  homepage "https://github.com/no-way-labs/caldron"
  version "0.1.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/no-way-labs/caldron/releases/download/v0.1.0/mitt-macos-aarch64.tar.gz"
      sha256 "PLACEHOLDER_ARM64_SHA256"
    else
      url "https://github.com/no-way-labs/caldron/releases/download/v0.1.0/mitt-macos-x86_64.tar.gz"
      sha256 "PLACEHOLDER_X86_64_SHA256"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/no-way-labs/caldron/releases/download/v0.1.0/mitt-linux-aarch64.tar.gz"
      sha256 "PLACEHOLDER_LINUX_ARM64_SHA256"
    else
      url "https://github.com/no-way-labs/caldron/releases/download/v0.1.0/mitt-linux-x86_64.tar.gz"
      sha256 "PLACEHOLDER_LINUX_X86_64_SHA256"
    end
  end

  def install
    bin.install "mitt"
  end

  test do
    assert_match "mitt", shell_output("#{bin}/mitt --help 2>&1", 1)
  end
end
