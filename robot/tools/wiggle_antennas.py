"""Wiggle Reachy's antennas briefly (playful gesture)."""

import logging
from typing import Any, Dict

from reachy_mini.reachy_mini import INIT_ANTENNAS_JOINT_POSITIONS
from reachy_mini_conversation_app.tools.core_tools import Tool, ToolDependencies
from reachy_mini_conversation_app.dance_emotion_moves import GotoQueueMove


logger = logging.getLogger(__name__)


class WiggleAntennas(Tool):
    """Quick antenna oscillation — a playful acknowledgement."""

    name = "wiggle_antennas"
    description = "Briefly oscillate the antennas as a playful gesture (excitement, acknowledgement, greeting)."
    needs_response = False
    parameters_schema = {"type": "object", "properties": {}, "required": []}

    async def __call__(self, deps: ToolDependencies, **kwargs: Any) -> Dict[str, Any]:
        logger.info("Tool call: wiggle_antennas")
        r0, l0 = INIT_ANTENNAS_JOINT_POSITIONS
        current_head_pose = deps.reachy_mini.get_current_head_pose()
        head_joints, antenna_joints = deps.reachy_mini.get_current_joint_positions()
        current_body_yaw = float(head_joints[0])
        current_r, current_l = float(antenna_joints[0]), float(antenna_joints[1])

        offset = 0.4  # radians (~23°) each side
        sequence = [
            ((r0 - offset, l0 + offset), (current_r, current_l)),
            ((r0 + offset, l0 - offset), (r0 - offset, l0 + offset)),
            ((r0 - offset, l0 + offset), (r0 + offset, l0 - offset)),
            ((r0, l0), (r0 - offset, l0 + offset)),
        ]
        for target, start in sequence:
            deps.movement_manager.queue_move(
                GotoQueueMove(
                    target_head_pose=current_head_pose,
                    start_head_pose=current_head_pose,
                    target_antennas=target,
                    start_antennas=start,
                    target_body_yaw=current_body_yaw,
                    start_body_yaw=current_body_yaw,
                    duration=0.35,
                )
            )
        return {"status": "queued", "action": "wiggle_antennas"}
