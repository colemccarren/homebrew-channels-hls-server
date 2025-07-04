# channels-hls-server
A simple tool to stream a channel from your Channels DVR instance. Easily spin up an external-facing HLS server for a specified duration of time.

## Requirements

- python 3
- ffmpeg
- On your home network, forward **TCP port 8090** to the internal IP address of the machine running the script.
- **Important:** This script **must** run on the same machine as your Channels DVR server.

## Install

```bash
brew install colemccarren/homebrew-channels-hls-server/channels-hls-server
```

If you're on an older machine and Homebrew can't install `ffmpeg` properly:

1. Download a static `ffmpeg` binary from [https://evermeet.cx/ffmpeg/](https://evermeet.cx/ffmpeg/).
2. Install without dependencies:

```bash
brew install --ignore-dependencies colemccarren/homebrew-channels-hls-server/channels-hls-server
```

## Usage

Run:

```bash
channels-hls-server
```

Then specify:

- The **channel** you want to stream (based on your Channels DVR guide).
- The **duration** you want to serve it (e.g., `1h` for 1 hour).

The script will:

- Check your machine's local IP address.
- Spin up the necessary Python and `ffmpeg` processes.
- Serve a remote HLS (`.m3u8`) stream via your public IP address!

To watch, open the URL in VLC or a web browser that supports HLS playback.

## Stopping the Server

Out and about? Started `channels-hls-server` over an SSH session from your mobile phone and lost your terminal window? You can always stop the background processes by running:

```bash
channels-hls-server stop
```
