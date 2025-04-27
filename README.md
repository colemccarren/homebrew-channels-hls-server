# channels-hls-server

Simple HLS server for sharing a live channel from your Channels DVR server.

## Requirements

- python 3
- ffmpeg
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

## Stopping the Server

If you started `channels-hls-server` over an SSH session and your terminal was interrupted, you can stop the background processes by running:

```bash
channels-hls-server stop
```
