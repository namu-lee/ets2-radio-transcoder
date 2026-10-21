# ETS2 Radio Transcoder

Turn online radio stations into local MP3 streams that Euro Truck Simulator 2 (ETS2) can play.

## Workflow

1. Add your stations to `stations.csv` using the `name,url,category` format.
2. Run `docker compose up -d` to start Icecast and FFmpeg.
3. On startup, `transcode.sh` generates `live_streams.sii`. FFmpeg converts each station to a 128 kbps MP3 stream and sends it to Icecast.
4. Icecast serves the streams at `http://127.0.0.1:8000/`. If a source drops, the transcoder automatically reconnects.
5. With ETS2 closed, copy `live_streams.sii` to `Documents/Euro Truck Simulator 2/`. Launch the game and select a station from the in-game radio.

**Note:** Run Docker on the same computer as ETS2, since the generated stream URLs use `127.0.0.1`.

To stop the services, run `docker compose down`.
