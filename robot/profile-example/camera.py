"""Hybrid camera tool: capture a frame, ask a vision model, return text.

Overrides the built-in `camera` tool. The default behaviour returns the JPEG
inline so the chat LLM (which must be a VLM) can see it. With this override,
the chat LLM stays a plain text model (e.g. llama3.1:8b, which handles tool
calling well but is not multimodal); the frame goes to a dedicated VLM
(qwen2.5vl, llama3.2-vision, etc.) that returns a text description, which
becomes the tool result the chat LLM speaks.

Env overrides (usually set in the daemon's systemd drop-in):
    REACHY_VLM_BASE_URL   default http://<NODE_IP>:31434/v1
    REACHY_VLM_MODEL      default qwen2.5vl:7b
    REACHY_VLM_TIMEOUT_S  default 90
    REACHY_VLM_MAX_TOKENS default 220
"""

import base64
import logging
import os
from typing import Any, Dict

import httpx

from reachy_mini_conversation_app.tools.core_tools import Tool, ToolDependencies
from reachy_mini_conversation_app.camera_frame_encoding import encode_bgr_frame_as_jpeg


logger = logging.getLogger(__name__)

VLM_BASE_URL = os.environ.get("REACHY_VLM_BASE_URL", "http://127.0.0.1:11434/v1")
VLM_MODEL = os.environ.get("REACHY_VLM_MODEL", "qwen2.5vl:7b")
VLM_TIMEOUT_S = float(os.environ.get("REACHY_VLM_TIMEOUT_S", "90"))
VLM_MAX_TOKENS = int(os.environ.get("REACHY_VLM_MAX_TOKENS", "220"))


class Camera(Tool):
    """Take a picture with the camera and ask a vision model a question about it."""

    name = "camera"
    description = (
        "Take a picture with the camera and ask a vision model a question about what you see. "
        "Use this when the user asks what is in front of you, what they look like, what objects "
        "are visible, to read text, or to identify anything by sight."
    )
    parameters_schema = {
        "type": "object",
        "properties": {
            "question": {
                "type": "string",
                "description": "The question to ask about the picture (natural language).",
            },
        },
        "required": ["question"],
    }

    async def __call__(self, deps: ToolDependencies, **kwargs: Any) -> Dict[str, Any]:
        question = (kwargs.get("question") or "").strip()
        if not question:
            return {"error": "question must be a non-empty string"}

        logger.info("Tool call: camera question=%s", question[:120])

        if not deps.camera_enabled:
            return {"error": "Camera is disabled"}

        frame = deps.reachy_mini.media.get_frame()
        if frame is None:
            return {"error": "No frame available"}

        jpeg_bytes = encode_bgr_frame_as_jpeg(frame)
        b64 = base64.b64encode(jpeg_bytes).decode("utf-8")

        payload = {
            "model": VLM_MODEL,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": question},
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                    ],
                }
            ],
            "max_tokens": VLM_MAX_TOKENS,
            "stream": False,
        }

        try:
            async with httpx.AsyncClient(timeout=VLM_TIMEOUT_S) as client:
                r = await client.post(f"{VLM_BASE_URL}/chat/completions", json=payload)
                r.raise_for_status()
                data = r.json()
        except Exception as e:
            logger.exception("VLM request failed")
            return {"error": f"vision model request failed: {type(e).__name__}: {e}"}

        try:
            description = data["choices"][0]["message"]["content"].strip()
        except (KeyError, IndexError, TypeError) as e:
            logger.error("Unexpected VLM response shape: %s", data)
            return {"error": f"unexpected vision model response: {e}"}

        if not description:
            return {"error": "vision model returned empty description"}

        return {"description": description}
