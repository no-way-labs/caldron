class Mitt < Formula
  desc "Encrypted file transfer CLI tool"
  homepage "https://github.com/no-way-labs/caldron"
  version "0.2.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/no-way-labs/caldron/releases/download/v0.1.0/mitt-macos-aarch64.tar.gz"
      sha256 "43fbf870b67e343facbbfe5e1e40b5b150330764be8f416810823104c9bd5615"
    else
      url "https://github.com/no-way-labs/caldron/releases/download/v0.1.0/mitt-macos-x86_64.tar.gz"
      sha256 "d1c98f79a2a47d0242b2c9deec031e0599abe958d0257a533fd4c058afe1441c"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/no-way-labs/caldron/releases/download/v0.1.0/mitt-linux-aarch64.tar.gz"
      sha256 "537134374902fb53ecde632a471f43661c91ad30a5876e930197e8eb76709e36"
    else
      url "https://github.com/no-way-labs/caldron/releases/download/v0.1.0/mitt-linux-x86_64.tar.gz"
      sha256 "d9763c581efd5a18c18991ac45e08ff527d60e35185c97aa8febe3c6daf3ed77"
    end
  end

  def install
    bin.install "mitt"
  end

  test do
    assert_match "mitt", shell_output("#{bin}/mitt --help 2>&1", 1)
  end
end
