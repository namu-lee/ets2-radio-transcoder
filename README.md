# ETS2 Radio Transcoder

ETS2 Radio Transcoder converts online radio stations into local MP3 streams for Euro Truck Simulator 2 (ETS2).

## Quick start

1. Add stations to `stations.csv` in `name,url,category` format.
2. Start Icecast and FFmpeg with `docker compose up -d`.
3. `transcode.sh` generates `live_streams.sii`, then FFmpeg converts each station to 128 kbps MP3 and sends it to Icecast.
4. Icecast serves the streams at `http://127.0.0.1:8000/`. If a station disconnects, the transcoder retries automatically.
5. Close ETS2, copy `live_streams.sii` to `Documents/Euro Truck Simulator 2/`, then reopen the game and select a station from the radio menu.

Run Docker on the same computer as ETS2. The generated stream URLs use `127.0.0.1`.

Stop the services with `docker compose down`.
