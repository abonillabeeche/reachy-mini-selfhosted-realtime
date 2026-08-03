# Mac controls — the `reachy` CLI, SwiftBar menu, and self-test

Everything in [`mac/`](../mac/) drives a Reachy Mini Wireless from a Mac over
the LAN, talking to the robot daemon's REST API on `:8000` (plus SSH for the
few things the API doesn't expose — volume on an external DAC, the mic
push-to-talk gate, profile switching, live mic/camera streams).

Nothing here needs the Kubernetes s2s backend — these are direct robot
controls and work as soon as the robot is powered on and on the network.

## Requirements

On the **Mac** (control machine):

| Tool | Why | Install |
|---|---|---|
| `curl`, `python3`, `osascript`, `say`, `afconvert`, `afplay` | Core — REST calls, JSON parsing, TTS, dialogs. | Built into macOS |
| `sshpass` | Password SSH to the robot (volume, mic gate, profiles, streams). | `brew install esolitos/ipa/sshpass` |
| `sox` (`play`) | `reachy listen` plays the robot's mic stream locally. | `brew install sox` |
| SwiftBar | The menu-bar widget. | `brew install --cask swiftbar` |
| Hammerspoon (`hs`) | *Optional* — the "Talk 4s" on-screen countdown button. | `brew install --cask hammerspoon` |

On the **robot** (Reachy Mini Wireless, stock Pollen software):

- Reachable over WiFi; daemon REST on `http://<ROBOT_IP>:8000`.
- SSH enabled — default creds `pollen` / `root` (see
  [prereqs](02-prereqs.md)).
- Internet on first use of `dance`/`sing`/`emotion`: the daemon lazily
  downloads and caches the move libraries
  `pollen-robotics/reachy-mini-dances-library` (19 silent dances) and
  `pollen-robotics/reachy-mini-emotions-library` (~85 emotions, each with a
  sidecar `.ogg` — Reachy's own chirps/whistles). After first play they're
  cached under `~/.cache/huggingface` on the robot and work offline.
- *(Optional, this build's hardware)* an external USB DAC (shows as ALSA card
  `Audio_1`) wired to a `reachymini_audio_sink` dmix device in
  `/etc/asound.conf`. All daemon audio (say/whisper/emotion sounds) routes
  there. If you don't have the DAC, audio comes out the built-in speaker and
  the `volume`/`mute` subcommands (which target `Audio_1` over SSH) won't
  apply — use the daemon's `/api/volume` instead.

## One-time setup

1. **Config file** — create `~/.config/reachy/env` (git-ignored; every helper
   sources it):

   ```bash
   mkdir -p ~/.config/reachy
   cat > ~/.config/reachy/env <<'EOF'
   ROBOT_IP=10.0.0.154      # your robot's LAN IP (find via router / reachy-mini.local)
   ROBOT_USER=pollen
   ROBOT_PASS=root          # default; change if you changed it
   EOF
   chmod 600 ~/.config/reachy/env
   ```

2. **Put the helpers on your PATH** — symlink them into `~/bin` (SwiftBar
   calls them by these exact names):

   ```bash
   mkdir -p ~/bin
   R="$PWD/mac"          # run from the repo root
   for s in reachy reachy-happy reachy-happy-toggle reachy-listen reachy-listen-toggle \
            reachy-see reachy-open-control reachy-selftest; do
     src="$R/${s}.sh"; [ "$s" = reachy ] && src="$R/reachy"
     ln -sf "$src" ~/bin/"$s"
   done
   chmod +x "$R"/*.sh "$R"/reachy
   # ensure ~/bin is on PATH (zsh):
   grep -q 'export PATH="$HOME/bin' ~/.zshrc || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
   ```

3. **Verify** — `reachy status`, then `reachy test` (see below).

## The `reachy` CLI

`reachy <subcommand>` — run `reachy help` for the full list.

**Lifecycle & state**
- `reachy wake` / `reachy sleep` — bring her up (motors, smooth 5 s head lift,
  start conversation app) / fold down.
- `reachy status` — motors, head pitch, DAC volume, running app.
- `reachy test` — the self-test suite (see below).

**Physical actions** (auto-enable motors; work even while the conversation
app is running)
- `reachy dance` — one random silent dance.
- `reachy dance-long` — a ~5-dance routine, chained.
- `reachy waddle` — side-to-side sway.
- `reachy sing` / `reachy sing-long` — a medley of Reachy's own audio-emotions
  (motion **plus** her chirps/whistles), paced so each clip's audio lands.
- `reachy stayin-alive` / `reachy kill-bill` — her two baked-in whistled tunes
  (the long `dance2`/`dance3` emotion clips).
- `reachy emotion [name]` — play a specific emotion (motion + audio); random
  from the upbeat pool if no name.

**Voice**
- `reachy say "text"` — speak via macOS TTS through the robot's speaker
  (uploads a WAV, plays via `/api/media/play_sound`).
- `reachy whisper "text"` — same, using the soft macOS **Whisper** voice.

**Happy Mode** — silent random background moves for ambience
- `reachy happy start|stop|toggle|status` — every ~10–20 s she does a random
  *gentle, silent* dance (dances carry no audio). Skips a beat if a move is
  already running so it never fights the conversation app. Runs as a detached
  background loop (PID in `$TMPDIR/reachy-happy.pid`).

**Audio & mic** (external DAC + XMOS mic, over SSH)
- `reachy volume <0-100>` / `reachy mute` / `reachy unmute` — DAC level.
- `reachy mic on|off|toggle` / `reachy talk [secs]` — push-to-talk gate (keeps
  Reachy from hearing her own speaker).

**Personality**
- `reachy profile [name]` — list / switch conversation-app persona (restarts
  the app).

**Live streams** (Ctrl-C to stop)
- `reachy listen` — stream the robot mic to the Mac (`sox`).
- `reachy see` — live camera view.

## SwiftBar widget

`mac/swiftbar/reachy.10s.sh` — live status + one-click controls in the menu
bar (icon shows 🤖 awake / 💤 asleep / ✨ Happy Mode / 🔴 mic hot).

Install:
1. `brew install --cask swiftbar`, launch it, point its plugin folder at
   `~/Documents/SwiftBar`.
2. Symlink the plugin (edits stay live): `ln -sf "$PWD/mac/swiftbar/reachy.10s.sh" ~/Documents/SwiftBar/reachy.10s.sh`
3. `chmod +x mac/swiftbar/reachy.10s.sh`. The `10s` in the name = refresh
   every 10 s.

It surfaces: status block, 🎭 Personality submenu, mic toggle + Talk, Wake/
Sleep, 🗣 Speak / 🤫 Whisper, a **🎪 Actions** submenu (Dance / Dance-long /
Waddle / Sing / Sing-longer / Stayin' Alive / Kill Bill / Emotion), ✨ Happy
Mode toggle, Listen / Camera, and a Volume submenu. It reads
`REACHY_CLI` (default `~/bin/reachy`) and the same `~/.config/reachy/env`.

## Self-test

`reachy test` (a.k.a. `mac/reachy-selftest.sh`) exercises the whole surface and
prints PASS/FAIL:

- connectivity (daemon, backend `running`, SSH), motors enable;
- **motion** — waddle / dance / emotion / stayin-alive / kill-bill each
  confirmed by `/api/move/running` actually going non-empty;
- **audio** — say / whisper / emotion-audio confirmed by the daemon's
  `reachymini_audio_sink` playback log incrementing;
- **Happy Mode** — start → produces a move → stop, clean.

It stops each move between checks so it runs fast, exits non-zero on any
failure, and `FULL=1 reachy test` also runs the long `sing` medley. Run it
after any change, or when something "isn't working," to localize the fault.

## Gotchas found the hard way

- **Speak/Whisper silent** → `say-reachy.sh` used `$ROBOT` (host:port); if
  unset it defaulted to the wrong IP. It now derives from `ROBOT_IP`. If audio
  still doesn't play, run `reachy test` — the audio checks pin it down.
- **Camera dark / app won't start after `listen`/`see`/`open-control`** →
  those release daemon media; the media pipeline (incl. the `:8443` WebRTC
  signaling server) only runs while media is *acquired*. Re-acquire with
  `curl -X POST http://<ROBOT_IP>:8000/api/media/acquire`. See
  [troubleshooting](07-troubleshooting.md).
- **Emotion audio needs the DAC/media up.** `sing`/`emotion` play their `.ogg`
  through the daemon media server → `reachymini_audio_sink`. If media is
  released you get motion but no sound.
