# ETS2 Radio Transcoder

ETS2 Radio Transcoder converts online radio streams to MP3 and hosts them locally for playback in Euro Truck Simulator 2 (ETS2).

## Quick start

These instructions use Windows PowerShell. Install Git and Docker Desktop first. Start Docker Desktop, and launch ETS2 at least once so its Documents folder exists.

1. Clone the repository and start the streams:

   ```powershell
   git clone https://github.com/namu-lee/ets2-radio-transcoder.git
   cd ets2-radio-transcoder
   docker compose up -d
   ```

2. Wait for `live_streams.sii` to appear in the repository folder. Close ETS2, then copy the file to the game's Documents folder:

   ```powershell
   $ets2Dir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Euro Truck Simulator 2'
   Copy-Item .\live_streams.sii "$ets2Dir\live_streams.sii" -Force
   ```

   This overwrites the existing radio list. Back up your current `live_streams.sii` if you want to keep it.

3. Launch ETS2, open the Radio menu, and choose a station. Leave Docker running while listening.

To stop the streams:

```powershell
docker compose down
```

Docker and ETS2 must run on the same PC, since the stream URLs use `127.0.0.1`.

## Adding stations

The included `stations.csv` is ready to use. To add another station, append a row in `name,url,category` format. Use a direct audio stream URL.

After saving the file, restart the transcoder:

```powershell
docker compose restart ffmpeg
```

Wait for `live_streams.sii` to be regenerated, then close ETS2 and copy it to the game's Documents folder again using the command above.
