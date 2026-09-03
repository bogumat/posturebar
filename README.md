# PostureBar

PostureBar is a lightweight, native macOS menu-bar app that uses your webcam
to detect slouching. It shows a green tick for good posture and a red spiral
for bad posture.

- Five posture checks per second
- One-hour red, green, and gray history graph
- Configurable buzzer after sustained slouching
- Automatically releases the camera during calls
- No third-party dependencies, accounts, uploads, or saved camera frames

## Install on macOS

PostureBar requires macOS 13 or later. Follow these steps exactly.

### 1. Install Apple's Command Line Tools

Open **Terminal** from **Applications → Utilities**, paste this command, and
press Return:

```sh
xcode-select --install
```

Complete the installer window before continuing. If Terminal says the tools
are already installed, continue to step 2.

### 2. Download and install PostureBar

Paste this entire block into Terminal:

```sh
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/bogumat/posturebar.git
cd posturebar
make install
```

Wait for the final line to show:

```text
/Users/YOUR-NAME/Applications/PostureBar.app
```

### 3. Launch PostureBar

Run:

```sh
open ~/Applications/PostureBar.app
```

When macOS asks for camera access, click **Allow**. Sit upright and reasonably
still for about four seconds while PostureBar calibrates. Its icon will then
appear in the menu bar.

PostureBar prefers a camera with `UGREEN` in its name, then another external
camera, then the built-in camera. Click the menu-bar icon to choose a different
camera or recalibrate.

## Using PostureBar

- Green tick: posture looks good
- Red spiral: you are slouching
- Gray ring: paused, calibrating, or not recording

The menu contains a one-hour posture graph. Green bars mean good posture, red
bars mean bad posture, and gray bars mean no recording.

By default, the buzzer begins after 10 seconds of continuous slouching. Use
**Buzz After** to choose 1s, 2s, 5s, 10s, 20s, 30s, or 1 minute. Use **Sound
Alerts** to mute it without pausing posture monitoring.

PostureBar releases the camera when another app uses the microphone or camera,
then resumes automatically when the call ends. You can also pause it manually.

## Optional: Raycast shortcuts

Raycast is not required. These shortcuts only provide quick ways to start,
stop, or open the project.

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

## Update

Quit PostureBar, then run:

```sh
cd ~/Projects/posturebar
git pull
make install
open ~/Applications/PostureBar.app
```

## Development

```sh
make test   # Run checks
make app    # Build .build/PostureBar.app
```

PostureBar uses AppKit, AVFoundation, Vision, and CoreAudio. Camera frames are
processed locally and never stored. Only sparse posture states and timestamps
are retained for the one-hour graph.
