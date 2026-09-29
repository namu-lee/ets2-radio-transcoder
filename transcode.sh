#!/bin/sh

STATIONS_FILE="/app/stations.csv"
SII_FILE="/app/live_streams.sii"

workers=""

stop_all() {
    echo "[Radio] Stopping all streams..."

    for p in $workers; do
        kill -TERM "$p" 2>/dev/null || true
    done

    wait
    exit 0
}

trap stop_all TERM INT

generate_sii() {
    count=0

    while IFS=',' read -r NAME URL MOUNT; do
        NAME="$(printf '%s' "$NAME" | tr -d '\r')"

        [ "$NAME" = "name" ] && continue
        [ -z "$NAME" ] && continue

        count=$((count + 1))
    done < "$STATIONS_FILE"

    tmp="${SII_FILE}.tmp"

    {
        echo "SiiNunit"
        echo "{"
        echo "live_stream_def : .live_streams {"
        echo "    stream_data: $count"
        echo ""

        index=0

        while IFS=',' read -r NAME URL MOUNT; do
            NAME="$(printf '%s' "$NAME" | tr -d '\r')"
            MOUNT="$(printf '%s' "$MOUNT" | tr -d '\r')"

            [ "$NAME" = "name" ] && continue
            [ -z "$NAME" ] && continue

            echo "    stream_data[$index]: \"http://127.0.0.1:8000/$MOUNT|$NAME|Radio|KR|128|1\""

            index=$((index + 1))
        done < "$STATIONS_FILE"

        echo "}"
        echo "}"
    } > "$tmp"

    mv "$tmp" "$SII_FILE"

    echo "[Radio] Generated live_streams.sii with $count stations"
}

run() {
    NAME="$1"
    URL="$2"
    MOUNT="$3"

    while true; do
        echo "[$NAME] Starting stream"

        ffmpeg \
            -nostdin \
            -hide_banner \
            -loglevel warning \
            -user_agent "Mozilla/5.0" \
            -rw_timeout 5000000 \
            -reconnect 1 \
            -reconnect_streamed 1 \
            -reconnect_on_network_error 1 \
            -reconnect_on_http_error "4xx,5xx" \
            -reconnect_delay_max 2 \
            -http_persistent 0 \
            -i "$URL" \
            -map 0:a:0 \
            -vn \
            -c:a libmp3lame \
            -b:a 128k \
            -ar 44100 \
            -ac 2 \
            -content_type audio/mpeg \
            -ice_name "$NAME" \
            -ice_public 0 \
            -f mp3 \
            "icecast://source:ets2radio@icecast:8000/$MOUNT" &

        child=$!

        trap 'kill -TERM "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 0' TERM INT

        wait "$child" || true

        trap - TERM INT

        echo "[$NAME] Stream disconnected. Reconnecting..."
        sleep 5
    done
}

if [ ! -f "$STATIONS_FILE" ]; then
    echo "[Radio] Station config not found: $STATIONS_FILE"
    exit 1
fi

echo "[Radio] Generating ETS2 radio list..."
generate_sii

echo "[Radio] Waiting for Icecast..."
sleep 5

echo "[Radio] Starting all streams"

while IFS=',' read -r NAME URL MOUNT; do
    NAME="$(printf '%s' "$NAME" | tr -d '\r')"
    URL="$(printf '%s' "$URL" | tr -d '\r')"
    MOUNT="$(printf '%s' "$MOUNT" | tr -d '\r')"

    [ "$NAME" = "name" ] && continue
    [ -z "$NAME" ] && continue

    run \
        "$NAME" \
        "$URL" \
        "$MOUNT" &

    workers="$workers $!"
done < "$STATIONS_FILE"

echo "[Radio] All streams started"

wait

