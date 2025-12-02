class Mitt < Formula
  desc "Encrypted file transfer CLI tool"
  homepage "https://github.com/no-way-labs/caldron"
  version "0.3.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/no-way-labs/caldron/releases/download/v0.3.0/mitt-macos-aarch64.tar.gz"
      sha256 "1e11baa5b39728b368b79399b456a167879312490fb7941cfd202ded4f059e5e"
    else
      url "https://github.com/no-way-labs/caldron/releases/download/v0.3.0/mitt-macos-x86_64.tar.gz"
      sha256 "049e3bd67a46fc362d6ba631338e53e4ad59ada0789afa7238b2805ed87c3637"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/no-way-labs/caldron/releases/download/v0.3.0/mitt-linux-aarch64.tar.gz"
      sha256 "b8486b8af606f8a64a294146dc68dd4e6bf60c945427d037d0c297a1cda47cd1"
    else
      url "https://github.com/no-way-labs/caldron/releases/download/v0.3.0/mitt-linux-x86_64.tar.gz"
      sha256 "2fb8f44f3209c940d1292617df1c6ee6f27edcc5759d004e300a7641af1ff497"
    end
  end

  def install
    bin.install "mitt"
  end

  test do
    assert_match "mitt", shell_output("#{bin}/mitt --help 2>&1", 1)
  end
end
