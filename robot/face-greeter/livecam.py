#!/usr/bin/env python3
"""Live camera helper for face-greeter testing — runs in the daemon venv
(needs cv2 + reachy_mini + gstreamer). Opens a WebRTC *consumer* to the
daemon's local camera stream (localhost:8443), so it grabs live frames
alongside the running conversation app without touching the robot lock.

  livecam.py capture              # grab frames, report faces, save capture.jpg
  livecam.py enroll-live <name>   # learn a face from the live camera
  livecam.py identify-live        # who is Reachy looking at right now?
"""
import sys, time, os
import numpy as np
import cv2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from reachy_mini.media.media_manager import MediaManager, MediaBackend  # noqa: E402
from face_greeter import FaceGreeter  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def open_cam(timeout=15.0):
    # LOCAL = GStreamer shared-memory IPC reader of the daemon's camera; works
    # as a second consumer alongside the app. (It also inits audio, but that
    # only touches the speaker when *we* play a sound — and greetings are gated
    # by is_busy() so they never interrupt a playing move/song.)
    m = MediaManager(backend=MediaBackend.LOCAL)
    t0 = time.time()
    while time.time() - t0 < timeout:
        if m.get_frame() is not None:
            return m
        time.sleep(0.2)
    return m  # caller checks get_frame()


def grab(m, n=10, gap=0.25):
    frames = []
    for _ in range(n):
        f = m.get_frame()
        if f is not None:
            frames.append(f)
        time.sleep(gap)
    return frames


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "capture"
    fg = FaceGreeter()
    m = open_cam()
    if m.get_frame() is None:
        print("ERROR: no frames from camera stream (is the robot awake / media acquired?)")
        return
    print("camera stream connected.")

    if cmd == "capture":
        frames = grab(m, n=12)
        best = None
        for fr in frames:
            faces = fg.detect(fr)
            if len(faces):
                areas = faces[:, 2] * faces[:, 3]
                i = int(np.argmax(areas))
                if best is None or areas[i] > best[1]:
                    best = (fr, float(areas[i]), faces[i])
        print(f"grabbed {len(frames)} frames")
        if best is None:
            print("no face detected — make sure you're in view, well lit")
            cv2.imwrite(os.path.join(HERE, "capture.jpg"), frames[-1])
            return
        fr, area, face = best
        fr = fr.copy()   # camera frames are read-only
        x, y, w, h = face[:4].astype(int)
        cv2.rectangle(fr, (x, y), (x + w, y + h), (0, 255, 0), 2)
        cv2.imwrite(os.path.join(HERE, "capture.jpg"), fr)
        print(f"FACE DETECTED (biggest {w}x{h}px). Saved capture.jpg")

    elif cmd == "enroll-live":
        name = sys.argv[2]
        frames = grab(m, n=14, gap=0.3)
        embs = []
        for fr in frames:
            e = fg.biggest_face_embedding(fr)
            if e is not None:
                embs.append(e)
        if not embs:
            print("no faces captured — try again, face the camera"); return
        # keep the most consistent samples (drop outliers by mean cosine)
        E = np.array([e / (np.linalg.norm(e) + 1e-9) for e in embs])
        c = E.mean(0); c /= (np.linalg.norm(c) + 1e-9)
        keep = [embs[i] for i in range(len(embs)) if (E[i] @ c) > 0.5]
        fg.enroll(name, keep or embs)
        print(f"Enrolled {name} from {len(keep or embs)}/{len(frames)} frames. DB now: {len(fg.names)}.")

    elif cmd == "identify-live":
        frames = grab(m, n=8)
        votes = {}
        for fr in frames:
            r = fg.recognize(fr)
            if r:
                votes[r[0]] = votes.get(r[0], 0) + 1
        if votes:
            who = max(votes, key=votes.get)
            print(f"Recognized: {who}  ({votes[who]}/{len(frames)} frames)")
        else:
            print("Nobody recognized (unknown face or no face).")

    elif cmd == "watch":
        import urllib.request, json
        cooldown = float(os.environ.get("GREET_COOLDOWN", "60"))
        min_w = int(os.environ.get("GREET_MIN_FACE_W", "26"))    # on the resized frame
        need = int(os.environ.get("GREET_MIN_FRAMES", "3"))      # consecutive frames to confirm
        det_w = int(os.environ.get("DET_WIDTH", "960"))          # downscale before detection
        cadence = float(os.environ.get("GREET_CADENCE", "0.8"))  # secs between recognitions
        last = {}
        streak = {"name": None, "count": 0}

        def face_present():
            # Cheap: reuse the daemon's own face detector (it's tracking anyway).
            # We only spend CPU on recognition when someone is actually there.
            try:
                r = urllib.request.urlopen(
                    "http://localhost:8000/api/media/tracking/face", timeout=2)
                return bool((json.loads(r.read()).get("face_target") or {}).get("detected"))
            except Exception:
                return False

        def is_busy():
            # Don't step on a playing move/song (e.g. a SwiftBar action) — its
            # audio shares the one speaker and our greeting would cut it off.
            try:
                r = urllib.request.urlopen("http://localhost:8000/api/move/running", timeout=3)
                return len(json.loads(r.read()) or []) > 0
            except Exception:
                return False

        def greet(name):
            if is_busy():
                print(f"  (skip greeting {name}: something is already playing)")
                return False
            fname = f"greet_{name}.wav"
            body = json.dumps({"file": fname}).encode()
            try:
                req = urllib.request.Request(
                    "http://localhost:8000/api/media/play_sound",
                    data=body, headers={"Content-Type": "application/json"})
                urllib.request.urlopen(req, timeout=5).read()
                print(f"  👋 greeted {name}")
                return True
            except Exception as e:
                print(f"  (greeting failed for {name}: {e})")
                return False

        print(f"watching (SCHED_IDLE) thr={os.environ.get('FACE_MATCH_THRESHOLD','0.40')} "
              f"min_w={min_w}@{det_w} need={need} cadence={cadence}s cooldown={cooldown}s")
        while True:
            fr = m.get_frame()
            hit = None
            if fr is not None:
                # Detect on a downscaled frame (YuNet on 1080p is the CPU hog),
                # then embed each candidate on the FULL-res face for quality.
                if fr.shape[1] > det_w:
                    s = det_w / fr.shape[1]
                    small = cv2.resize(fr, (0, 0), fx=s, fy=s)
                else:
                    s, small = 1.0, fr
                faces = fg.detect(small)
                # sort biggest-first, check up to 4 — match ANY enrolled face,
                # not just the biggest (a bigger stranger must not mask you)
                if len(faces):
                    order = np.argsort(-(faces[:, 2] * faces[:, 3]))
                    best = 0.0
                    for i in order[:4]:
                        face = faces[i]
                        if int(face[2]) < min_w:
                            continue
                        if s != 1.0:
                            face = face.copy()
                            face[:14] = face[:14] / s   # bbox+5 landmarks -> full-res
                        name, score = fg.match(fg.embedding(fr, face))
                        if name and score > best:
                            best, hit = score, name
            if hit and hit == streak["name"]:
                streak["count"] += 1
            else:
                streak = {"name": hit, "count": 1 if hit else 0}
            if hit and streak["count"] >= need:
                now = time.time()
                if now - last.get(hit, 0) > cooldown:
                    print(f"greeting {hit}")
                    if greet(hit):
                        last[hit] = now
            time.sleep(cadence)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
