class Perspective < Formula
  desc "Swift CLI for Apple Foundation Models and MLX models"
  homepage "https://github.com/techopolis/PerspectiveCLI"
  url "https://github.com/techopolis/PerspectiveCLI/releases/download/0.14.0/perspective-cli-0.14.0-macos-arm64.tar.gz"
  sha256 "57710ba28305fdc49f12d169ec02b674993f92c49fff909f55f2f554a45ffaf2"
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
