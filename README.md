# Church Streamer

A desktop successor to the original ChurchStreamer: a
volunteer-friendly desktop app for starting a church livestream and local
recording without requiring operators to understand broadcast software.

Supported platforms are macOS, Windows, and desktop Linux. Android and iOS are
intentionally out of scope.

## Current milestone

This first slice runs on Windows, macOS, and Linux and includes:

- a responsive service setup and preview dashboard;
- automatic discovery and live preview of connected cameras;
- independent 0–1000 ms synchronization delay for every camera and audio input;
- suggested service titles and YouTube privacy controls;
- a local recording option; and
- a tested stream that supports multiple cameras and audio.

Local recording, YouTube authorization, live-event provisioning, and FFmpeg
RTMP publishing are implemented. 

## Run it

```sh
flutter pub get
flutter run -d windows   # or macos / linux
```

Run checks with `flutter analyze` and `flutter test`.

## YouTube API setup

1. In Google Cloud Console, enable **YouTube Data API v3**.
2. Configure the OAuth consent screen and add the channel operators as test
   users while the app remains in testing.
3. Create an OAuth client ID with application type **Desktop app**.
4. Download its JSON credentials, rename the file to `client_secrets.json`, and
   place it in the project root. This filename is ignored by Git.
5. Restart Church Streamer and select **Connect YouTube**. Authorization opens
   in the system browser and returns.

After the first successful authorization, the credentials are kept in
the operating system's secure credential store. Church Streamer attempts to
reconnect and validate that same channel on every startup. If Google revokes
the authorization, the app returns to the Connect YouTube state.

Use `client_secrets.example.json` as a reference only. Never commit the
downloaded credentials or expose the RTMP ingestion URL, which contains the
channel's stream key.

### Linux camera prerequisites

The Linux camera backend uses GStreamer and V4L2. On Ubuntu or Debian, install:

```sh
sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-good pulseaudio-utils ffmpeg \
  libsecret-1-0 libsecret-1-dev
```

YouTube reconnection stores OAuth refresh credentials through libsecret. A
Secret Service-compatible keyring must also be running; GNOME Keyring and KDE
Wallet normally provide one automatically in their respective desktop
environments. Minimal window manager sessions may need to start a keyring
service explicitly.

MacOS asks for camera permission on first launch. Windows requires no additional
camera runtime setup.

## Media permissions

Naturally, the app requires camera and audio input access, along with file access to save off a recording.