-- Reachy Mini — push-to-talk hotkeys + on-screen countdown
--
--   Hold  ⌘⌥⌃T         → mic open while held, release to close (walkie-talkie)
--   Tap   ⌘⌥⌃Space      → timed talk: mic opens, 4-3-2-1 countdown, auto-mutes
--   SwiftBar "Talk" item calls reachyTalk() via the `hs` CLI (no Terminal).
--
-- Requires: Hammerspoon granted Accessibility permission, and an SSH
-- ControlMaster host "reachy-mini-ptt" (see ~/.ssh/config) for instant toggles.

require("hs.ipc")  -- enables the `hs` CLI (SwiftBar Talk button)

-- Read robot SSH password from git-ignored ~/.config/reachy/env (ROBOT_PASS=...)
local function readRobotPass()
  local h = os.getenv("HOME")
  local fp = io.open(h .. "/.config/reachy/env", "r")
  if not fp then return "" end
  for line in fp:lines() do
    local v = line:match("^%s*ROBOT_PASS=(.+)%s*$")
    if v then v = v:gsub('^"', ''):gsub('"$', ''); fp:close(); return v end
  end
  fp:close(); return ""
end

local ROBOT_PASS = readRobotPass()
local SSH_HOST   = "reachy-mini-ptt"
local MIC_ON  = "amixer -c 0 sset Headset,0 cap >/dev/null 2>&1; amixer -c 0 sset Headset,1 cap >/dev/null 2>&1"
local MIC_OFF = "amixer -c 0 sset Headset,0 nocap >/dev/null 2>&1; amixer -c 0 sset Headset,1 nocap >/dev/null 2>&1"

local function runMic(cmd)
  hs.task.new("/usr/bin/env", nil,
    { "sshpass", "-p", ROBOT_PASS, "ssh", SSH_HOST, cmd }):start()
end

-- ── Hold-to-talk ────────────────────────────────────────────────
local holding = false
local function holdStart()
  if holding then return end
  holding = true
  runMic(MIC_ON)
  hs.alert.closeAll()
  hs.alert.show("🎙 Talking…", { textSize = 22 }, 3600)
end
local function holdStop()
  if not holding then return end
  holding = false
  runMic(MIC_OFF)
  hs.alert.closeAll()
  hs.alert.show("🔇 Mic off", { textSize = 16 }, 0.6)
end
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "T", holdStart, holdStop)

-- ── Timed talk with countdown (global so `hs -c "reachyTalk(4)"` works) ──
local talkTimer = nil
function reachyTalk(secs)
  secs = tonumber(secs) or 4
  if talkTimer then talkTimer:stop(); talkTimer = nil end
  runMic(MIC_ON)
  local remaining = secs
  hs.alert.closeAll()
  hs.alert.show("🎙 Talk now!  " .. remaining, { textSize = 30 }, 1.05)
  talkTimer = hs.timer.doEvery(1, function()
    remaining = remaining - 1
    hs.alert.closeAll()
    if remaining > 0 then
      hs.alert.show("🎙 " .. remaining, { textSize = 30 }, 1.05)
    else
      talkTimer:stop(); talkTimer = nil
      runMic(MIC_OFF)
      hs.alert.show("🔇 Mic muted — Reachy's turn", { textSize = 20 }, 1.4)
    end
  end)
end
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "space", function() reachyTalk(4) end)

hs.alert.show("Reachy push-to-talk ready — hold ⌘⌥⌃T, or tap ⌘⌥⌃Space", 2)
