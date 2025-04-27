#!/bin/bash

# --- Auto-Screen Logic (Optional - add this back if you want it) ---
# Check if the script is already running inside a screen session
# if [ -z "$STY" ]; then
#   SCREEN_SESSION_NAME="channels-hls-server_session"
#   echo "Not in screen. Starting script in detached screen session: $SCREEN_SESSION_NAME"
#   screen -dmS "$SCREEN_SESSION_NAME" "$0" "$@"
#   echo "Script is now running in the background within screen. Detaching..."
#   echo "You can reattach with: screen -r $SCREEN_SESSION_NAME"
#   exit 0
# fi
# echo "Running inside screen session $STY. Proceeding with script execution."
# --- End Auto-Screen Logic ---


# --- CONFIGURATION ---
HLS_DIR="hls_output"      # Directory for HLS files
HLS_PORT=8090             # Port for the local HTTP server
DEFAULT_DURATION="1h"     # Default duration if user enters nothing

# --- Process IDs ---
FFMPEG_PID=""
SERVER_PID=""
# Store PIDs in a file to make them accessible for the stop command
PID_FILE="$HLS_DIR/pids.pid"


# --- CLEANUP FUNCTION ---
# This function will be called upon exit or interrupt to stop processes
cleanup() {
    echo # Add a newline for cleaner output
    echo "🛑 Stopping processes..."

    # Read PIDs from file if available
    if [ -f "$PID_FILE" ]; then
        read -r FFMPEG_PID SERVER_PID < "$PID_FILE"
        echo "    Read PIDs from $PID_FILE: ffmpeg=$FFMPEG_PID, server=$SERVER_PID"
        # Clean up the PID file
        rm "$PID_FILE"
    fi


    # Check if PIDs are set and the processes exist before trying to kill
    if [ -n "$FFMPEG_PID" ] && kill -0 "$FFMPEG_PID" 2>/dev/null; then
        echo "    Killing ffmpeg (PID: $FFMPEG_PID)..."
        # Use kill with a signal like SIGTERM (-15) for a gentler shutdown
        # or just kill for default SIGTERM
        kill "$FFMPEG_PID"
        # Wait briefly for ffmpeg to exit cleanly. Use command substitution
        # with timeout if wait hangs, but 2>/dev/null handles typical issues.
        wait "$FFMPEG_PID" 2>/dev/null
    fi
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "    Killing python server (PID: $SERVER_PID)..."
        kill "$SERVER_PID"
        wait "$SERVER_PID" 2>/dev/null # Wait briefly for server to exit cleanly
    fi

    echo "🧹 Cleaning up temporary HLS files..."
    # Add a basic safety check for the directory name before removing
    # Use [[ ... ]] for safer string comparison in bash
    if [[ "$HLS_DIR" == "hls_output" ]]; then
         # Add -v for verbose removal if desired: rm -rf -v "$HLS_DIR"
         rm -rf "$HLS_DIR"
         echo "    Removed directory: $HLS_DIR"
    else
         echo "    Skipping removal of HLS_DIR as it doesn't match expected name: $HLS_DIR"
    fi

    echo "✅ Stream shutdown complete."

    # Reset the trap and exit cleanly
    # Only exit if not explicitly called by the stop command handler
    if [ "$COMMAND" != "stop" ]; then
        trap - SIGINT SIGTERM EXIT
        # Using exit 0 after cleanup is standard
        exit 0
    fi
}

# --- COMMAND HANDLING ---
# Check the first argument for specific commands
COMMAND="$1"
if [ "$COMMAND" == "stop" ]; then
    echo "Received stop command."
    # Call the cleanup function directly
    cleanup
    exit 0 # Exit after handling the stop command
fi

# --- TRAP SIGNALS ---
# Call the cleanup function if the script receives SIGINT (Ctrl+C), SIGTERM, or on normal EXIT
# These traps are set AFTER the command handling, so 'stop' bypasses the trap
trap cleanup SIGINT SIGTERM EXIT

# --- INITIAL CLEANUP of potentially old instances ---
echo "🧹 Cleaning up any old processes and files from previous runs..."
# Use pkill -f with more specific patterns and add a short sleep
pkill -f "ffmpeg .* $HLS_PORT/stream.m3u8" || true # Target ffmpeg writing to the HLS dir
pkill -f "python3 -m http.server $HLS_PORT" || true # Target python server on the specific port

# Add a small delay to allow processes to shut down and release the port
sleep 2 # Added sleep

# Safety check before removing directory
if [[ "$HLS_DIR" == "hls_output" ]]; then
    rm -rf "$HLS_DIR"
fi
# Recreate the HLS directory
mkdir "$HLS_DIR" || { echo "❌ ERROR: Failed to create directory '$HLS_DIR'"; exit 1; } # Exit if dir creation fails

# --- DURATION CONVERSION FUNCTION ---
# Converts a duration string (e.g., 1h, 30m, 2h30m, 120s, or just 120) to seconds
# (Keep this function as is)
calculate_seconds() {
    local duration_str="$1"
    local total_seconds=0
    local num unit

    if [[ "$duration_str" =~ ^[0-9]+$ ]]; then
        echo "$duration_str"
        return 0
    fi

    if [[ "$duration_str" =~ ([0-9]+)h ]]; then
        num=${BASH_REMATCH[1]}
        total_seconds=$((total_seconds + num * 3600))
        duration_str=${duration_str/${num}h/}
    fi

    if [[ "$duration_str" =~ ([0-9]+)m ]]; then
        num=${BASH_REMATCH[1]}
        total_seconds=$((total_seconds + num * 60))
         duration_str=${duration_str/${num}m/}
    fi

    if [[ "$duration_str" =~ ([0-9]+)s ]]; then
        num=${BASH_REMATCH[1]}
        total_seconds=$((total_seconds + num))
         duration_str=${duration_str/${num}s/}
    fi

    duration_str=$(echo "$duration_str" | tr -d '[:space:]')
    if [[ -n "$duration_str" ]]; then
         echo "❌ ERROR: Invalid characters or format in duration: $1 (Remaining: '$duration_str')" >&2
         return 1
    fi

    echo "$total_seconds"
    return 0
}


# --- DETERMINE LOCAL IP ADDRESS ---
# (Keep this section as is)
echo "💻 Attempting to determine local IP address..."
LOCAL_IP=""

if command -v ip > /dev/null; then
    LOCAL_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n 1)
fi

if [ -z "$LOCAL_IP" ]; then
    if command -v ifconfig > /dev/null; then
        LOCAL_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1)
    fi
fi

if [ -z "$LOCAL_IP" ]; then
    echo "❌ ERROR: Could not automatically determine local IP address." >&2 # Send to stderr
    exit 1
fi

echo "✅ Determined local IP address: $LOCAL_IP"
DVR_IP="$LOCAL_IP"


# --- GET USER INPUT ---
# Shift the arguments to ignore the first argument (the command, if any)
shift || true # shift once, ignore error if no arguments

read -p "Enter Channel Number (e.g., 1001, 13.1): " CHANNEL_NUM
CHANNEL_NUM=$(echo "$CHANNEL_NUM" | tr -d '[:space:]')
if ! [[ "$CHANNEL_NUM" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "❌ ERROR: Channel number '$CHANNEL_NUM' must be a valid number format (e.g., 1001 or 13.1)." >&2 # Send to stderr
    exit 1
fi

read -p "Enter duration (e.g., 1h, 30m, 2h30m, 90s, or just 120) [Default: $DEFAULT_DURATION]: " DURATION_INPUT
DURATION="${DURATION_INPUT:-$DEFAULT_DURATION}"
DURATION=$(echo "$DURATION" | tr -d '[:space:]')


# --- CONVERT DURATION TO SECONDS ---
SLEEP_SECONDS=$(calculate_seconds "$DURATION")
if [ $? -ne 0 ]; then
    exit 1
fi
echo "⏱️ Calculated sleep time: $SLEEP_SECONDS seconds"


# --- GET PUBLIC IP ADDRESS ---
# (Keep this section as is)
echo "🌍 Attempting to determine public IP address..."
PUBLIC_IP=$(curl -s --max-time 10 "https://checkip.amazonaws.com")
IP_STATUS=$?

if [ "$IP_STATUS" -eq 0 ] && [[ "$PUBLIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "✅ Public IP determined: $PUBLIC_IP"
else
    PUBLIC_IP="<Could not determine public IP>"
    echo "⚠️ Warning: Failed to determine public IP." >&2 # Send to stderr
    if [ "$IP_STATUS" -ne 0 ]; then
         echo "    Curl command failed with status $IP_STATUS (check internet connection or if 'curl' is installed)." >&2 # Send to stderr
    else
         echo "    Curl returned non-IP output: '$PUBLIC_IP'" >&2 # Send to stderr
    fi
    echo "    Using placeholder for external access." >&2 # Send to stderr
fi


# --- CONSTRUCT STREAM URL ---
STREAM_URL="http://$DVR_IP:8089/devices/ANY/channels/$CHANNEL_NUM/stream.mpg?codec=copy&format=ts"
echo "🎯 Pulling stream source from Channels DVR at: $STREAM_URL"
echo "⏳ Will attempt to stream for: $DURATION (or $SLEEP_SECONDS seconds)"


# --- START FFMPEG ---
echo "🎬 Starting ffmpeg..."
ffmpeg -re -i "$STREAM_URL" \
    -c:v copy -c:a copy \
    -f hls \
    -hls_time 4 \
    -hls_list_size 5 \
    -hls_flags delete_segments+omit_endlist \
    -hls_segment_filename "$HLS_DIR/segment%03d.ts" \
    "$HLS_DIR/stream.m3u8" > "$HLS_DIR/ffmpeg.log" 2>&1 & # Redirect logs to file in HLS_DIR

FFMPEG_PID=$!
# Brief pause to let ffmpeg start or fail quickly
sleep 3
if ! kill -0 "$FFMPEG_PID" 2>/dev/null; then
    echo "❌ ERROR: ffmpeg failed to start. Check stream URL, network, and if Channels DVR is running." >&2 # Send to stderr
    echo "    Log content ($HLS_DIR/ffmpeg.log):" >&2 # Send to stderr
    cat "$HLS_DIR/ffmpeg.log" >&2 # Send to stderr
    exit 1
fi
echo "    ffmpeg running with PID: $FFMPEG_PID"

# --- START PYTHON SERVER ---
echo "🌐 Starting HTTP server on port $HLS_PORT to serve files from '$HLS_DIR'..."
cd "$HLS_DIR" || { echo "❌ ERROR: Could not change directory to '$HLS_DIR'"; exit 1; } >&2 # Send to stderr
python3 -m http.server "$HLS_PORT" > ../server.log 2>&1 & # Redirect logs to a file outside HLS_DIR
SERVER_PID=$!
cd .. || { echo "❌ ERROR: Could not change back from '$HLS_DIR'"; exit 1; } >&2 # Send to stderr
sleep 1
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "❌ ERROR: Python HTTP server failed to start. Check server.log for details." >&2 # Send to stderr
    echo "    Log content (server.log):" >&2 # Send to stderr
    cat server.log >&2 # Send to stderr
    exit 1
fi
echo "    Server running with PID: $SERVER_PID"

# --- SAVE PIDs ---
# Save the PIDs to a file for the stop command to use later
echo "$FFMPEG_PID $SERVER_PID" > "$HLS_DIR/pids.pid"


# --- WAIT FOR DURATION ---
echo "🚀 Stream should now be running."
echo "    Access HLS stream locally at: http://$LOCAL_IP:$HLS_PORT/stream.m3u8"

if [[ "$PUBLIC_IP" == "<Could not determine public IP>" ]]; then
    echo "    External access: Could not automatically determine public IP. Replace <Could not determine public IP> with your actual public IP if needed, ensuring port $HLS_PORT is forwarded."
else
    echo "    Access HLS stream externally at: http://$PUBLIC_IP:$HLS_PORT/stream.m3u8"
    echo "    (Requires port $HLS_PORT to be forwarded on your router to this machine's local IP: $LOCAL_IP)"
fi

echo "    Streaming will run for approximately $DURATION."
echo "    Press Ctrl+C to stop earlier."
echo "    Or run 'channels-hls-server stop' from another terminal."


sleep "$SLEEP_SECONDS"

# --- CLEANUP AFTER DURATION ---
echo # Newline
echo "⏳ Timer finished ($DURATION elapsed). Initiating shutdown..."
# The EXIT trap will trigger cleanup

# Note: This final echo is unlikely to be reached in normal execution
# echo "Script finished normally after duration."
