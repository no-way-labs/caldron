class Mitt < Formula
  desc "Encrypted file transfer CLI tool"
  homepage "https://github.com/no-way-labs/caldron"
  version "0.4.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/no-way-labs/caldron/releases/download/v0.4.0/mitt-macos-aarch64.tar.gz"
      sha256 "ff7d6b56b93bd567cbb5cc820a2df206116b280015173224cc0f675620bf3bd4"
    else
      url "https://github.com/no-way-labs/caldron/releases/download/v0.4.0/mitt-macos-x86_64.tar.gz"
      sha256 "cd6e957320374b9d2c19993e9edfe5017439e25f7ee92b7219aaa2fe35684bf6"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/no-way-labs/caldron/releases/download/v0.4.0/mitt-linux-aarch64.tar.gz"
      sha256 "eb14d2bb257c53df5054e3c14b350d358103acbc6a9d0d4f6d6a969f6fbe5d28"
    else
      url "https://github.com/no-way-labs/caldron/releases/download/v0.4.0/mitt-linux-x86_64.tar.gz"
      sha256 "0b408d3226a5ac2387e498cc8b80967e44dd09eae21e3270ea0a102c1b8cb1f2"
    end
  end

  def install
    bin.install "mitt"
  end

  test do
    assert_match "mitt", shell_output("#{bin}/mitt --help 2>&1", 1)
  end
end
