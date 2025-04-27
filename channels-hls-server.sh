#!/bin/bash

# --- CONFIGURATION ---
HLS_DIR="hls_output"      # Directory for HLS files
HLS_PORT=8090             # Port for the local HTTP server
DEFAULT_DURATION="1h"     # Default duration if user enters nothing

# --- Process IDs ---
FFMPEG_PID=""
SERVER_PID=""

# --- DURATION CONVERSION FUNCTION ---
# Converts a duration string (e.g., 1h, 30m, 2h30m, 120s, or just 120) to seconds
calculate_seconds() {
    local duration_str="$1"
    local total_seconds=0
    local num unit

    # Handle pure number (assumed seconds)
    if [[ "$duration_str" =~ ^[0-9]+$ ]]; then
        echo "$duration_str"
        return 0
    fi

    # Use regex to extract hours, minutes, and seconds
    # Handles formats like 1h, 30m, 120s, 2h30m, 5m10s, 1h5m20s (in any order ideally, though regex processes left to right)

    # Extract Hours
    if [[ "$duration_str" =~ ([0-9]+)h ]]; then
        num=${BASH_REMATCH[1]}
        total_seconds=$((total_seconds + num * 3600))
        # Remove the processed part, being careful with string manipulation
        duration_str=${duration_str/${num}h/}
    fi

    # Extract Minutes
    if [[ "$duration_str" =~ ([0-9]+)m ]]; then
        num=${BASH_REMATCH[1]}
        total_seconds=$((total_seconds + num * 60))
         # Remove the processed part
        duration_str=${duration_str/${num}m/}
    fi

    # Extract Seconds
    if [[ "$duration_str" =~ ([0-9]+)s ]]; then
        num=${BASH_REMATCH[1]}
        total_seconds=$((total_seconds + num))
         # Remove the processed part
        duration_str=${duration_str/${num}s/}
    fi

    # Check if any non-numeric or invalid parts remain
    # Remove potential leading/trailing whitespace first for a cleaner check
    duration_str=$(echo "$duration_str" | tr -d '[:space:]')
    if [[ -n "$duration_str" ]]; then
         echo "❌ ERROR: Invalid characters or format in duration: $1 (Remaining: '$duration_str')" >&2 # Output error to stderr
         return 1 # Indicate failure
    fi

    echo "$total_seconds"
    return 0
}


# --- CLEANUP FUNCTION ---
# This function will be called upon exit or interrupt to stop processes
cleanup() {
    echo # Add a newline for cleaner output
    echo "🛑 Stopping processes..."
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
    trap - SIGINT SIGTERM EXIT
    # Using exit 0 after cleanup is standard
    exit 0
}

# --- TRAP SIGNALS ---
# Call the cleanup function if the script receives SIGINT (Ctrl+C), SIGTERM, or on normal EXIT
trap cleanup SIGINT SIGTERM EXIT

# --- INITIAL CLEANUP of potentially old instances ---
echo "🧹 Cleaning up any old processes and files from previous runs..."
# Make pkill patterns slightly more specific if possible
# Using a broader pattern for ffmpeg might catch more instances
pkill -f "ffmpeg.*http://.*:8089/devices/ANY/channels/.*stream\.mpg" || true # Add || true to prevent exit if no process found
pkill -f "python3 -m http.server $HLS_PORT" || true # Add || true to prevent exit if no process found
# Safety check before removing directory
if [[ "$HLS_DIR" == "hls_output" ]]; then
    rm -rf "$HLS_DIR"
fi
mkdir "$HLS_DIR" || { echo "❌ ERROR: Failed to create directory '$HLS_DIR'"; exit 1; } # Exit if dir creation fails

# --- DETERMINE LOCAL IP ADDRESS ---
echo "💻 Attempting to determine local IP address..."
LOCAL_IP=""

# Try 'ip' command first (modern Linux)
if command -v ip > /dev/null; then
    LOCAL_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n 1)
fi

# If 'ip' didn't find it or isn't available (e.g., older systems, macOS), try 'ifconfig'
if [ -z "$LOCAL_IP" ]; then
    if command -v ifconfig > /dev/null; then
        LOCAL_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1)
    fi
fi

# Fallback if no non-loopback IP found (unlikely if connected to a network)
if [ -z "$LOCAL_IP" ]; then
    echo "❌ ERROR: Could not automatically determine local IP address."
    # Cleanup function is called automatically due to 'trap ... EXIT'
    exit 1
fi

echo "✅ Determined local IP address: $LOCAL_IP"

# Set the DVR IP to the determined local IP
DVR_IP="$LOCAL_IP"


# --- GET USER INPUT ---
# Removed the prompt for DVR IP address
read -p "Enter Channel Number (e.g., 1001, 13.1): " CHANNEL_NUM
# Added optional leading/trailing whitespace trimming
CHANNEL_NUM=$(echo "$CHANNEL_NUM" | tr -d '[:space:]')
# Allows numbers like 123, 123.45, but not .123 or 123.
if ! [[ "$CHANNEL_NUM" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "❌ ERROR: Channel number '$CHANNEL_NUM' must be a valid number format (e.g., 1001 or 13.1)."
    exit 1
fi

read -p "Enter duration (e.g., 1h, 30m, 2h30m, 90s, or just 120) [Default: $DEFAULT_DURATION]: " DURATION_INPUT
# Use default if user presses Enter without typing anything
DURATION="${DURATION_INPUT:-$DEFAULT_DURATION}"
# Added optional leading/trailing whitespace trimming
DURATION=$(echo "$DURATION" | tr -d '[:space:]')

# --- CONVERT DURATION TO SECONDS ---
SLEEP_SECONDS=$(calculate_seconds "$DURATION")
if [ $? -ne 0 ]; then # Check the return code of the calculate_seconds function
    # The function itself prints the error message
    exit 1 # Exit via trap due to the error
fi
echo "⏱️ Calculated sleep time: $SLEEP_SECONDS seconds"

# --- GET PUBLIC IP ADDRESS ---
echo "🌍 Attempting to determine public IP address..."
# Use a service that returns only the IP address (e.g., checkip.amazonaws.com, icanhazip.com)
# Add a timeout (--max-time) in case the service is slow or unreachable
# Use -s for silent output from curl
PUBLIC_IP=$(curl -s --max-time 10 "https://checkip.amazonaws.com")
IP_STATUS=$? # Capture the exit status of curl

# Check if curl succeeded and the output looks like an IP address
if [ "$IP_STATUS" -eq 0 ] && [[ "$PUBLIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "✅ Public IP determined: $PUBLIC_IP"
else
    # Set a placeholder message if lookup failed
    PUBLIC_IP="<Could not determine public IP>"
    echo "⚠️ Warning: Failed to determine public IP."
    if [ "$IP_STATUS" -ne 0 ]; then
         echo "    Curl command failed with status $IP_STATUS (check internet connection or if 'curl' is installed)."
    else
         echo "    Curl returned non-IP output: '$PUBLIC_IP'"
    fi
    echo "    Using placeholder for external access."
fi


# --- CONSTRUCT STREAM URL ---
# The stream source is Channels DVR on the same machine, using the determined local IP
STREAM_URL="http://$DVR_IP:8089/devices/ANY/channels/$CHANNEL_NUM/stream.mpg?codec=copy&format=ts"
echo "🎯 Pulling stream source from Channels DVR at: $STREAM_URL" # Updated message
echo "⏳ Will attempt to stream for: $DURATION (or $SLEEP_SECONDS seconds)"


# --- START FFMPEG ---
echo "🎬 Starting ffmpeg..."
# ffmpeg command remains the same, it will use the validated $CHANNEL_NUM via $STREAM_URL
# Output logs to files in the script's directory
ffmpeg -re -i "$STREAM_URL" \
    -c:v copy -c:a copy \
    -f hls \
    -hls_time 4 \
    -hls_list_size 5 \
    -hls_flags delete_segments+omit_endlist \
    -hls_segment_filename "$HLS_DIR/segment%03d.ts" \
    "$HLS_DIR/stream.m3u8" > ffmpeg.log 2>&1 & # Redirect stdout and stderr to ffmpeg.log

FFMPEG_PID=$!
# Brief pause to let ffmpeg start or fail quickly
sleep 3
# Check if ffmpeg actually started by sending signal 0 (checks existence)
if ! kill -0 "$FFMPEG_PID" 2>/dev/null; then
    echo "❌ ERROR: ffmpeg failed to start. Check stream URL, network, and if Channels DVR is running."
    echo "    Log content (ffmpeg.log):"
    cat ffmpeg.log
    # Cleanup function is called automatically due to 'trap ... EXIT'
    exit 1
fi
echo "    ffmpeg running with PID: $FFMPEG_PID"

# --- START PYTHON SERVER ---
echo "🌐 Starting HTTP server on port $HLS_PORT to serve files from '$HLS_DIR'..."
# Optional: Check if port is already in use (requires tools like lsof or ss)
# if ss -tuln | grep -q ":$HLS_PORT "; then
#     echo "⚠️ WARNING: Port $HLS_PORT might already be in use."
# fi
# Change directory to HLS_DIR before starting server
cd "$HLS_DIR" || { echo "❌ ERROR: Could not change directory to '$HLS_DIR'"; exit 1; }
# Start python server, redirect logs to a file outside HLS_DIR
python3 -m http.server "$HLS_PORT" > ../server.log 2>&1 &
SERVER_PID=$!
# Change back to the original directory
cd .. || { echo "❌ ERROR: Could not change back from '$HLS_DIR'"; exit 1; } # Add error check for cd ..
# Brief pause for server startup
sleep 1
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "❌ ERROR: Python HTTP server failed to start. Check server.log for details."
    echo "    Log content (server.log):"
    cat server.log
    # Cleanup function is called automatically due to 'trap ... EXIT'
    exit 1
fi
echo "    Server running with PID: $SERVER_PID"

# --- WAIT FOR DURATION ---
echo "🚀 Stream should now be running."
# Display the local IP for local access
echo "    Access HLS stream locally at: http://$LOCAL_IP:$HLS_PORT/stream.m3u8"

# Display the public IP for external access, or the placeholder
if [[ "$PUBLIC_IP" == "<Could not determine public IP>" ]]; then
    echo "    External access: Could not automatically determine public IP. Replace <Could not determine public IP> with your actual public IP if needed, ensuring port $HLS_PORT is forwarded."
else
    echo "    Access HLS stream externally at: http://$PUBLIC_IP:$HLS_PORT/stream.m3u8"
    echo "    (Requires port $HLS_PORT to be forwarded on your router to this machine's local IP: $LOCAL_IP)"
fi

echo "    Streaming will run for approximately $DURATION."
echo "    Press Ctrl+C to stop earlier."

# Sleep in the foreground for the calculated number of seconds.
# The 'trap' will handle Ctrl+C interruption.
# Use the calculated seconds here!
sleep "$SLEEP_SECONDS"

# --- CLEANUP AFTER DURATION ---
# If the script reaches this point, the sleep duration finished naturally.
echo # Newline
echo "⏳ Timer finished ($DURATION elapsed). Initiating shutdown..."
# The cleanup function is called automatically because of the 'trap ... EXIT'

# The script effectively ends here as the EXIT trap triggers 'cleanup' which exits.
# This final echo is unlikely to be reached in normal execution as cleanup exits.
# echo "Script finished normally after duration."