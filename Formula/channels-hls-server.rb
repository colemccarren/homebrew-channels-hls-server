class ChannelsHlsServer < Formula
  desc "Simple tool to stream a channel from your Channels DVR instance to an external-facing HLS server"
  homepage "https://github.com/colemccarren/homebrew-channels-hls-server"
  url "https://github.com/colemccarren/homebrew-channels-hls-server/releases/download/v0.1/channels-hls-server-0.1.tar.gz"
  version "0.1"
  sha256 "bc412dabc5c625f847db0730d22322584692c9c8c16713f91c237fb1c7de29c9"
  license "MIT"

  depends_on "bash"
  depends_on "ffmpeg"
  depends_on "python@3"

  def install
    bin.install "channels-hls-server.sh", => "channels-hls-server"
  end

  test do
    system "#{bin}/channels-hls-server", "--help"
  end
end

