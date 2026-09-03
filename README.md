# PostureBar

PostureBar is a lightweight, native macOS menu-bar app that uses your webcam
to detect slouching. It shows a green tick for good posture and a red spiral
for bad posture.

- Five posture checks per second
- One-hour red, green, and gray history graph
- Configurable buzzer after sustained slouching
- Automatically releases the camera during calls
- No third-party dependencies, accounts, uploads, or saved camera frames

## Download and install

PostureBar requires macOS 13 or later and supports Apple Silicon and Intel Macs.

1. Open the [latest release](https://github.com/bogumat/posturebar/releases/latest).
2. Under **Assets**, download `PostureBar-…-universal.zip`.
3. Open the downloaded ZIP, then drag `PostureBar.app` into **Applications**.
4. Double-click `PostureBar.app` in Applications.

The current release is not Apple-notarized, so macOS will block its first
launch. After attempting step 4:

1. Open **Apple menu → System Settings → Privacy & Security**.
2. Scroll to **Security** and click **Open Anyway** beside PostureBar.
3. Confirm with your password, then click **Open**.

This exception is needed only once. See [Apple's instructions for opening an
app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).

When asked for camera access, click **Allow**. Sit upright and reasonably still
for about four seconds while PostureBar calibrates. Calibration progress
restarts if you move significantly or the camera feed pauses, so it cannot save
a noisy baseline. Its icon will then appear in the menu bar.

On first launch, PostureBar prefers a plugged-in external webcam regardless of
brand, then falls back to the first available camera. A camera chosen from the
menu is remembered. Use the same menu to recalibrate.

## How detection works

PostureBar uses Apple's Vision framework to locate the largest face in a
low-resolution frame five times per second. Calibration records the face's
vertical position and apparent size while you sit upright. Later readings are
smoothed and compared with that baseline: a face moving lower is the main
slouch signal, while a face becoming larger (moving closer) is a secondary
signal. Three consistent readings are required before the indicator changes.

Keep the camera position fixed and recalibrate after moving the camera, chair,
or desk. PostureBar is a relative posture reminder, not an ergonomic or medical
assessment. Frames are processed in memory and immediately discarded.

## Using PostureBar

- Green tick: posture looks good
- Red spiral: you are slouching
- Gray ring: paused, calibrating, or not recording

The menu contains a one-hour posture graph. Green bars mean good posture, red
bars mean bad posture, and gray bars mean no recording.

By default, the buzzer begins after 10 seconds of continuous slouching. Use
**Buzz After** to choose 1s, 2s, 5s, 10s, 20s, 30s, or 1 minute. Use **Sound
Alerts** to mute it without pausing posture monitoring. Under **Buzz Volume**,
choose **Progressive** to start quietly and rise gradually, or **Constant
(Maximum)** to play every buzz at maximum volume.

PostureBar releases the camera when another app uses the microphone or camera,
then resumes automatically when the call ends. You can also pause it manually.

## Optional: Raycast shortcuts

Raycast is not required. These shortcuts only provide quick ways to start,
stop, or open the project. They require a local copy of this repository. If you
installed the downloadable app, run this first in Terminal:

```sh
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/bogumat/posturebar.git
```

1. Open **Raycast Settings (`⌘,`) → Extensions**.
2. Click **+** in the top-right and select **Add Script Directory**.
3. In the folder picker, press `⇧⌘G`.
4. Enter `~/Projects/posturebar/Raycast` and click **Open**.
5. Run **Reload Script Directories** in Raycast if the commands do not appear.

Raycast will add:

- **Start PostureBar**
- **Stop PostureBar**
- **Open Posture Project**

To assign a keyboard shortcut, find a command in Raycast, press `⌘K`, select
**Configure Command**, and record a hotkey.

## Update the downloaded app

Quit PostureBar, download the newest ZIP from the [releases
page](https://github.com/bogumat/posturebar/releases), and replace the existing
app in Applications. Your calibration and settings are preserved.

## Build from source

Install Apple's Command Line Tools:

```sh
xcode-select --install
```

Then clone, build, and install:

```sh
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/bogumat/posturebar.git
cd posturebar
make install
open ~/Applications/PostureBar.app
```

## Development

```sh
make test   # Run checks
make app    # Build .build/PostureBar.app
make package # Build a universal release ZIP in dist/
```

PostureBar uses AppKit, AVFoundation, Vision, and CoreAudio. Camera frames are
processed locally and never stored. Only sparse posture states and timestamps
are retained for the one-hour graph.
