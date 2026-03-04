class Perspective < Formula
  desc "Swift CLI for Apple Foundation Models and MLX models"
  homepage "https://github.com/techopolis/PerspectiveCLI"
  url "https://github.com/techopolis/PerspectiveCLI/releases/download/0.13.0/perspective-cli-0.13.0-macos-arm64.tar.gz"
  sha256 "67e3237d1449a035bd880a47f6c90e3d51e9af37bb6f8a2958df66dcc1bacd3c"
  license "MIT"

  depends_on arch: :arm64
  depends_on :macos

  def install
    bin.install "perspective"
    lib.install "mlx.metallib" if File.exist?("mlx.metallib")
  end

  test do
    assert_match "perspective", shell_output("#{bin}/perspective --help 2>&1", 1)
  end
end
