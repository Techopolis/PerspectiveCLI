class Perspective < Formula
  desc "Swift CLI for Apple Foundation Models and MLX models"
  homepage "https://github.com/techopolis/PerspectiveCLI"
  url "https://github.com/techopolis/PerspectiveCLI/releases/download/0.15.0-1-g0187008/perspective-cli-0.15.0-1-g0187008-macos-arm64.tar.gz"
  sha256 "011e7dfb1e4ac06ff7c56e148d39a324a8da5984160b693a051e3dd0c66efc4c"
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
