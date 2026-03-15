class Perspective < Formula
  desc "Swift CLI for Apple Foundation Models and MLX models"
  homepage "https://github.com/techopolis/PerspectiveCLI"
  url "https://github.com/techopolis/PerspectiveCLI/releases/download/0.2.0/perspective-cli-0.2.0-macos-arm64.tar.gz"
  sha256 "af670a36278bdcef16c9d1917bd935f12c04e4a374ca441c1cfd767c804515ac"
  license "MIT"

  depends_on arch: :arm64
  depends_on :macos

  def install
    # Both files must be colocated — mlx-swift uses dladdr to find mlx.metallib
    # next to the binary at runtime. Using libexec keeps them together while
    # symlinking the executable into bin/ on the PATH.
    libexec.install "perspective"
    libexec.install "mlx.metallib" if File.exist?("mlx.metallib")
    bin.install_symlink libexec/"perspective"
  end

  test do
    assert_match "perspective", shell_output("#{bin}/perspective --help 2>&1", 1)
  end
end
