# Church Streamer

A cross-platform successor to the original ChurchStreamer: a calm,
volunteer-friendly desktop app for starting a church livestream and local
recording without requiring operators to understand broadcast software.

## Current milestone

This first slice runs on Windows, macOS, and Linux and includes:

- a responsive service setup and preview dashboard;
- automatic discovery and live preview of connected cameras;
- suggested service titles and YouTube privacy controls;
- a local-recording option;
- a tested stream-session state machine; and
- a `StreamEngine` boundary ready for native capture.

Local recording is functional. YouTube authorization and live-event
provisioning are implemented; the FFmpeg RTMP media publisher is the next
transport milestone, so **Go live does not publish video yet**.

## Run it

```sh
flutter pub get
flutter run -d macos   # or windows / linux
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
   in the system browser and returns through a temporary localhost callback.

After the first successful authorization, the refresh credentials are kept in
the operating system's secure credential store. Church Streamer attempts to
reconnect and validate that same channel on every startup. If Google revokes
the authorization, the app returns to the Connect YouTube state.

Use `client_secrets.example.json` as a shape reference only. Never commit the
downloaded credentials or expose the RTMP ingestion URL, which contains the
channel's stream key.

### Linux camera prerequisites

The Linux camera backend uses GStreamer and V4L2. On Ubuntu or Debian, install:

```sh
sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-good pulseaudio-utils ffmpeg
```

macOS asks for camera permission on first launch. Windows requires no additional
camera runtime setup.

## Media permissions

Before opening capture devices, the app checks the platform's native permission
state. Previously granted access proceeds silently. On first use, macOS shows
an explanation followed by its native per-app prompts. Denied access does not
trigger repeated prompts; the dashboard instead gives recovery guidance and a
check-again action. Windows enforces its desktop-app privacy controls when
devices are opened. Linux enforces device, group, or sandbox permissions; there
is no universal native desktop prompt outside a portal-based package.

## Audio inputs

Connected audio capture devices are discovered after media access is granted.
Each enabled input is captured as 48 kHz mono PCM and displays a live dBFS
meter. The per-input control applies software gain from 0% to 200% to the PCM
stream that will feed the broadcast mixer. Turning an input off releases that
capture device completely.

## Proposed architecture

Flutter owns the user experience and session state. A native `StreamEngine`
owns device discovery, preview, encoding, recording, and RTMP/SRT output. The
most practical OBS-free first backend is FFmpeg on Windows/macOS and GStreamer
on Linux, hidden behind the same Dart interface. A destination adapter can then
create and bind YouTube Live broadcasts through OAuth.

Suggested next vertical slice:

1. enumerate cameras and microphones;
2. show a real local preview;
3. record a short local test file;
4. add encrypted credential storage and YouTube OAuth; then
5. publish RTMP and report dropped frames/bitrate to the dashboard.

This validates the hardest cross-platform media work before coupling it to a
live destination.
