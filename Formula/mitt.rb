class Mitt < Formula
  desc "Encrypted file transfer CLI tool"
  homepage "https://github.com/no-way-labs/caldron"
  version "0.2.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/no-way-labs/caldron/releases/download/v0.2.0/mitt-macos-aarch64.tar.gz"
      sha256 "ad131c12678a87040d62ddff547dcff3dfbe5bba3638fbc55ceb88b32f28260f"
    else
      url "https://github.com/no-way-labs/caldron/releases/download/v0.2.0/mitt-macos-x86_64.tar.gz"
      sha256 "1da830f215bad3612c2d1485e4c4e0df2f4690f51849a892e2c5430f3453f4ca"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/no-way-labs/caldron/releases/download/v0.2.0/mitt-linux-aarch64.tar.gz"
      sha256 "2091fca07a63717b863f9a23e973b28f0575dcd09f391d0f0478eb76f0202090"
    else
      url "https://github.com/no-way-labs/caldron/releases/download/v0.2.0/mitt-linux-x86_64.tar.gz"
      sha256 "162b14b5355c00d1fa479e1ce60cdaf858aa5a934e382062fbbde430d389b841"
    end
  end

  def install
    bin.install "mitt"
  end

  test do
    assert_match "mitt", shell_output("#{bin}/mitt --help 2>&1", 1)
  end
end
