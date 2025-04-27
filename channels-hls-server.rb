class ChannelsHlsServer < Formula
  desc "Simple tool to stream a channel from your Channels DVR instance to an external-facing HLS server"
  homepage "https://github.com/colemccarren/homebrew-channels-hls-server"
  url "https://raw.githubusercontent.com/colemccarren/homebrew-channels-hls-server/main/channels-hls-server"
  version "0.1"
  sha256 "d5558cd419c8d46bdc958064cb97f963d1ea793866414c025906ec15033512ed"
  license "MIT"

  depends_on "bash"
  depends_on "ffmpeg"
  depends_on "python@3"

  def install
    bin.install "channels-hls-server"
  end

  test do
    system "#{bin}/channels-hls-server", "--help"
  end
end

