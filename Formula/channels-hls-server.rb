class ChannelsHlsServer < Formula
  desc "Simple tool to stream a channel from your Channels DVR instance to an external-facing HLS server"
  homepage "https://github.com/colemccarren/homebrew-channels-hls-server"
  url "https://github.com/colemccarren/homebrew-channels-hls-server/releases/download/v0.1/channels-hls-server-0.1.tar.gz"
  version "0.1"
  sha256 "5245bceb26cde18632962b6be9ca173f38180a6c2539279ee31901ef7d49f97d"
  license "MIT"

  depends_on "bash"
  depends_on "ffmpeg"
  depends_on "python@3"

  def install
    bin.install "channels-hls-server.sh" => "channels-hls-server"
  end

  test do
    system "#{bin}/channels-hls-server", "--help"
  end
end

