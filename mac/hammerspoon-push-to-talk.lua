-- Reachy Mini — hold-to-talk (push-to-talk) hotkey
--
-- Hold  ⌘⌥⌃ + T  to open Reachy's mic; release to close it.
-- Walkie-talkie style: mic is open only while the keys are held, so Reachy
-- never hears its own voice from the external speaker (no feedback loop).
--
-- Requires: Hammerspoon granted Accessibility permission
-- (System Settings → Privacy & Security → Accessibility → enable Hammerspoon),
-- and an SSH ControlMaster host "reachy-mini-ptt" (see ~/.ssh/config) so the
-- mic toggle is near-instant.

-- Read robot SSH password from git-ignored ~/.config/reachy/env (ROBOT_PASS=...)
local function readRobotPass()
  local h = os.getenv("HOME")
  local fp = io.open(h .. "/.config/reachy/env", "r")
  if not fp then return "" end
  for line in fp:lines() do
    local v = line:match("^%s*ROBOT_PASS=(.+)%s*$")
    if v then v = v:gsub('^"',''):gsub('"$',''); fp:close(); return v end
  end
  fp:close(); return ""
end
local ROBOT_PASS = readRobotPass()   -- from ~/.config/reachy/env, not hardcoded
local SSH_HOST   = "reachy-mini-ptt" -- ControlMaster alias in ~/.ssh/config
local MIC_ON  = "amixer -c 0 sset Headset,0 cap >/dev/null 2>&1; amixer -c 0 sset Headset,1 cap >/dev/null 2>&1"
local MIC_OFF = "amixer -c 0 sset Headset,0 nocap >/dev/null 2>&1; amixer -c 0 sset Headset,1 nocap >/dev/null 2>&1"

local talking = false

local function runMic(cmd)
  -- async so the keypress never blocks the UI
  hs.task.new("/usr/bin/env", nil,
    { "sshpass", "-p", ROBOT_PASS, "ssh", SSH_HOST, cmd }):start()
end

local function talkStart()
  if talking then return end
  talking = true
  runMic(MIC_ON)
  hs.alert.closeAll()
  hs.alert.show("🎙 Talking…", { textSize = 20 }, 3600)
end

local function talkStop()
  if not talking then return end
  talking = false
  runMic(MIC_OFF)
  hs.alert.closeAll()
  hs.alert.show("🔇 Mic off", { textSize = 16 }, 0.6)
end

-- ⌘⌥⌃ + T : pressed = mic on, released = mic off
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "T", talkStart, talkStop)

hs.alert.show("Reachy push-to-talk ready — hold ⌘⌥⌃T to talk", 2)
