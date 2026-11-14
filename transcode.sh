#!/bin/sh

make_mount() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[[:space:]][[:space:]]*/-/g; s/[^a-z0-9-]//g'
}

stop_all() {
    echo "[Radio] Stopping all streams..."

    for p in $workers; do
        kill -TERM "$p" 2>/dev/null || true
    done

    wait
    exit 0
}

generate_sii() {
    count=0

    while IFS=',' read -r NAME URL CATEGORY; do
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

        while IFS=',' read -r NAME URL CATEGORY; do
            NAME="$(printf '%s' "$NAME" | tr -d '\r')"
            CATEGORY="$(printf '%s' "$CATEGORY" | tr -d '\r')"

            [ "$NAME" = "name" ] && continue
            [ -z "$NAME" ] && continue

            MOUNT="$(make_mount "$NAME").mp3"

            echo "    stream_data[$index]: \"http://127.0.0.1:8000/$MOUNT|$NAME|$CATEGORY|KR|128|1\""

            index=$((index + 1))
        done < "$STATIONS_FILE"

        echo "}"
        echo "}"
    } > "$tmp"

    mv "$tmp" "$SII_FILE"

    echo "[Radio] Generated live_streams.sii with $count stations"
}

resolve_stream() (
    source_url="$1"
    case "$source_url" in
        https://cfpwwwapi.kbs.co.kr/api/v1/landing/live/channel_code/*) provider=kbs ;;
        https://apis.sbs.co.kr/play-api/1.0/livestream/*) provider=sbs ;;
        *) jq -cn --arg url "$source_url" '{url: $url, expires: 0}'; exit ;;
    esac

    response=$(curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \
        "$source_url") || exit 1
    if [ "$provider" = kbs ]; then
        stream_url=$(printf '%s' "$response" | jq -er '.channel_item[0].service_url | strings') || exit 1
    else
        stream_url=$(printf '%s' "$response" | tr -d '\r\n')
    fi

    # Read expiry from the issued token; do not assume a fixed 12/48-hour TTL.
    jq -cen --arg url "$stream_url" --arg provider "$provider" '
        if ($url | test("^https?://[^[:space:]]+$") | not) then
            error("API returned an invalid stream URL")
        else . end |
        (if $provider == "kbs" then
            $url | capture("[?&]Policy=(?<policy>[^&#]+)").policy |
            gsub("-"; "+") | gsub("_"; "=") | gsub("~"; "/") |
            @base64d | fromjson | .Statement[0].Condition.DateLessThan["AWS:EpochTime"]
        else
            $url | capture("[?&]token=(?<token>[^&#]+)").token | split(".")[1] |
            gsub("-"; "+") | gsub("_"; "/") |
            @base64d | fromjson | .exp
        end) as $expires |
        if ($expires | type) != "number" then error("Missing stream expiry")
        elif $expires <= 0 or $expires != ($expires | floor) then error("Invalid stream expiry")
        else {url: $url, expires: $expires} end
    '
)

worker_sleep() {
    sleep "$1" &
    sleeper=$!
    wait "$sleeper" || true
    sleeper=""
}

stop_stream() {
    if [ -n "$child" ]; then
        kill -TERM "$child" 2>/dev/null || true
        # A stuck network operation must not prevent renewal or shutdown.
        stop_attempts=0
        while kill -0 "$child" 2>/dev/null && [ "$stop_attempts" -lt 5 ]; do
            sleep 1
            stop_attempts=$((stop_attempts + 1))
        done
        kill -KILL "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
        child=""
    fi
}

shutdown_worker() {
    trap '' TERM INT
    if [ -n "$sleeper" ]; then
        kill -TERM "$sleeper" 2>/dev/null || true
        wait "$sleeper" 2>/dev/null || true
    fi
    stop_stream
    exit 0
}

load_stream() {
    metadata=$(resolve_stream "$source_url") || return 1
    next_url=$(printf '%s' "$metadata" | jq -er '.url') || return 1
    next_expiry=$(printf '%s' "$metadata" | jq -er '.expires') || return 1
    if [ "$next_expiry" -ne 0 ] && [ "$next_expiry" -le "$(($(date +%s) + 5))" ]; then
        echo "[$station_name] API returned an expired or nearly expired URL" >&2
        return 1
    fi
}

start_stream() {
    expires="$next_expiry"
    refresh_at=$((expires - 60))
    if [ "$expires" -gt 0 ]; then
        echo "[$station_name] Starting stream; expires at $(date -u -d "@$expires" '+%Y-%m-%dT%H:%M:%SZ')"
    else
        echo "[$station_name] Starting stream"
    fi

    ffmpeg \
        -nostdin \
        -hide_banner \
        -loglevel warning \
        -user_agent "Mozilla/5.0" \
        -rw_timeout 5000000 \
        -reconnect 1 \
        -reconnect_streamed 1 \
        -reconnect_on_network_error 1 \
        -reconnect_on_http_error "429,5xx" \
        -reconnect_delay_max 2 \
        -reconnect_max_retries 3 \
        -reconnect_delay_total_max 10 \
        -seg_max_retry 3 \
        -i "$next_url" \
        -map 0:a:0 \
        -vn \
        -af "aresample=44100:async=1000:first_pts=0" \
        -c:a libmp3lame \
        -b:a 128k \
        -ar 44100 \
        -ac 2 \
        -content_type audio/mpeg \
        -ice_name "$station_name" \
        -ice_public 0 \
        -f mp3 \
        "icecast://source:ets2radio@icecast:8000/$mount" &
    child=$!
}

run() {
    station_name="$1"
    source_url="$2"
    mount="$3"
    child=""
    sleeper=""
    retry_delay=5
    trap shutdown_worker TERM INT

    while true; do
        if ! load_stream; then
            echo "[$station_name] URL lookup failed; retrying in ${retry_delay}s"
            worker_sleep "$retry_delay"
            retry_delay=$((retry_delay * 2))
            [ "$retry_delay" -le 60 ] || retry_delay=60
            continue
        fi
        retry_delay=5
        start_stream

        while kill -0 "$child" 2>/dev/null; do
            if [ "$expires" -eq 0 ]; then
                wait "$child" || true
                break
            fi
            now=$(date +%s)
            if [ "$now" -ge "$expires" ]; then
                echo "[$station_name] Stream URL expired; requesting a fresh URL"
                break
            fi
            if [ "$now" -ge "$refresh_at" ]; then
                # Keep playing while fetching. A cached URL with the same expiry
                # does not extend playback and must not trigger a restart loop.
                if load_stream && [ "$next_expiry" -gt "$expires" ]; then
                    echo "[$station_name] Renewing stream URL before expiry"
                    stop_stream
                    start_stream
                else
                    echo "[$station_name] No newer URL available; keeping current stream"
                    refresh_at=$(($(date +%s) + 15))
                fi
            fi
            delay=5
            remaining=$((expires - $(date +%s)))
            [ "$remaining" -gt 0 ] || continue
            [ "$remaining" -ge "$delay" ] || delay="$remaining"
            worker_sleep "$delay"
        done

        stop_stream
        echo "[$station_name] Stream disconnected; resolving URL again in 5s"
        worker_sleep 5
    done
}

main() {
    STATIONS_FILE="/app/stations.csv"
    SII_FILE="/app/live_streams.sii"
    workers=""
    trap stop_all TERM INT

    if [ ! -f "$STATIONS_FILE" ]; then
        echo "[Radio] Station config not found: $STATIONS_FILE"
        exit 1
    fi

    echo "[Radio] Generating ETS2 radio list..."
    generate_sii

    echo "[Radio] Waiting for Icecast..."
    sleep 5

    echo "[Radio] Starting all streams"

    while IFS=',' read -r NAME URL CATEGORY; do
        NAME="$(printf '%s' "$NAME" | tr -d '\r')"
        URL="$(printf '%s' "$URL" | tr -d '\r')"

        [ "$NAME" = "name" ] && continue
        [ -z "$NAME" ] && continue

        MOUNT="$(make_mount "$NAME").mp3"

        run \
            "$NAME" \
            "$URL" \
            "$MOUNT" &

        workers="$workers $!"
    done < "$STATIONS_FILE"

    echo "[Radio] All streams started"

    wait
}

main

