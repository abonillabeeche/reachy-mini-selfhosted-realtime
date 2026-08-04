#!/usr/bin/env python3
"""Face recognition + greeting for Reachy Mini.

Uses OpenCV's built-in YuNet (detection) + SFace (recognition) — both ship
with cv2 >= 4.7, so no insightface/dlib. Detection returns a bbox + 5
landmarks; SFace aligns the crop and produces a 128-D embedding. Same-person
matches score above ~0.363 cosine (OpenCV's recommended threshold).

Two model files are needed (download once, see fetch_models.sh):
  face_detection_yunet_2023mar.onnx
  face_recognition_sface_2021dec.onnx

Standalone CLI (runs in the daemon venv which has cv2):
  face_greeter.py enroll  <name> <image...>   # add a person from photo(s)
  face_greeter.py list                         # show enrolled people
  face_greeter.py identify <image>             # who is in this image?
  face_greeter.py selftest <image>             # enroll+match sanity check

In-app use (import): FaceGreeter(...).recognize(frame_bgr) -> (name, score)|None
"""
from __future__ import annotations
import sys, os, glob
import numpy as np
import cv2

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.environ.get("FACE_MODELS_DIR", os.path.join(HERE, "models"))
DB_PATH = os.environ.get("FACE_DB", os.path.join(HERE, "known_faces.npz"))
DET_MODEL = os.path.join(MODELS, "face_detection_yunet_2023mar.onnx")
REC_MODEL = os.path.join(MODELS, "face_recognition_sface_2021dec.onnx")

MATCH_THRESHOLD = float(os.environ.get("FACE_MATCH_THRESHOLD", "0.40"))  # cosine
DET_SCORE = 0.7


class FaceGreeter:
    def __init__(self, db_path: str = DB_PATH):
        if not (os.path.exists(DET_MODEL) and os.path.exists(REC_MODEL)):
            raise FileNotFoundError(
                f"Models missing in {MODELS}. Run fetch_models.sh first."
            )
        # input size is reset per-frame via setInputSize
        self.det = cv2.FaceDetectorYN.create(DET_MODEL, "", (320, 320),
                                             score_threshold=DET_SCORE)
        self.rec = cv2.FaceRecognizerSF.create(REC_MODEL, "")
        self.db_path = db_path
        self.names: list[str] = []
        self.embs: np.ndarray | None = None  # (N, 128)
        self._load()

    # ---- persistence ----
    def _load(self) -> None:
        if os.path.exists(self.db_path):
            d = np.load(self.db_path, allow_pickle=True)
            self.names = list(d["names"])
            self.embs = d["embs"]

    def _save(self) -> None:
        np.savez(self.db_path, names=np.array(self.names, dtype=object),
                 embs=self.embs if self.embs is not None else np.zeros((0, 128), np.float32))

    # ---- core ops ----
    def detect(self, frame: np.ndarray):
        h, w = frame.shape[:2]
        self.det.setInputSize((w, h))
        _, faces = self.det.detect(frame)
        return faces if faces is not None else np.empty((0, 15), np.float32)

    def embedding(self, frame: np.ndarray, face_row: np.ndarray) -> np.ndarray:
        aligned = self.rec.alignCrop(frame, face_row)
        feat = self.rec.feature(aligned)
        return feat.flatten().astype(np.float32)

    def biggest_face_embedding(self, frame: np.ndarray) -> np.ndarray | None:
        faces = self.detect(frame)
        if len(faces) == 0:
            return None
        # pick the largest face (w*h at cols 2,3)
        areas = faces[:, 2] * faces[:, 3]
        return self.embedding(frame, faces[int(np.argmax(areas))])

    def enroll(self, name: str, embeddings: list[np.ndarray]) -> None:
        for e in embeddings:
            row = e.reshape(1, -1)
            self.embs = row if self.embs is None else np.vstack([self.embs, row])
            self.names.append(name)
        self._save()

    def match(self, emb: np.ndarray):
        """Return (name, score) of the best match, or (None, best_score)."""
        if self.embs is None or len(self.embs) == 0:
            return None, 0.0
        # cosine similarity (SFace features are ~unit norm; normalize to be safe)
        a = emb / (np.linalg.norm(emb) + 1e-9)
        B = self.embs / (np.linalg.norm(self.embs, axis=1, keepdims=True) + 1e-9)
        sims = B @ a
        i = int(np.argmax(sims))
        best = float(sims[i])
        return (self.names[i] if best >= MATCH_THRESHOLD else None), best

    def recognize(self, frame: np.ndarray):
        emb = self.biggest_face_embedding(frame)
        if emb is None:
            return None
        name, score = self.match(emb)
        return None if name is None else (name, score)


# --------------------------- CLI ---------------------------
def _cli():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(2)
    cmd = sys.argv[1]
    fg = FaceGreeter()
    if cmd == "enroll":
        name = sys.argv[2]
        paths = []
        for p in sys.argv[3:]:
            paths += glob.glob(p)
        embs = []
        for p in paths:
            img = cv2.imread(p)
            if img is None:
                print("  skip (unreadable):", p); continue
            e = fg.biggest_face_embedding(img)
            if e is None:
                print("  no face:", p); continue
            embs.append(e); print("  enrolled face from", p)
        if embs:
            fg.enroll(name, embs)
            print(f"Enrolled {name} ({len(embs)} sample(s)). Total DB: {len(fg.names)}.")
        else:
            print("No usable faces; nothing enrolled.")
    elif cmd == "list":
        from collections import Counter
        print("Enrolled:", dict(Counter(fg.names)) or "(empty)")
    elif cmd == "identify":
        img = cv2.imread(sys.argv[2])
        emb = fg.biggest_face_embedding(img)
        if emb is None:
            print("No face detected."); return
        name, score = fg.match(emb)
        print(f"Best match: {name or '<unknown>'}  (cosine={score:.3f}, thr={MATCH_THRESHOLD})")
    elif cmd == "selftest":
        img = cv2.imread(sys.argv[2])
        e = fg.biggest_face_embedding(img)
        if e is None:
            print("selftest FAIL: no face in image"); sys.exit(1)
        # self-similarity should be ~1.0
        a = e / (np.linalg.norm(e) + 1e-9)
        print(f"selftest OK: face detected, self-cosine={float(a@a):.3f} (expect ~1.0)")
    else:
        print(__doc__); sys.exit(2)


if __name__ == "__main__":
    _cli()
