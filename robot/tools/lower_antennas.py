"""Lower Reachy's antennas to the folded-down / sleep position."""

import logging
from typing import Any, Dict

from reachy_mini.reachy_mini import SLEEP_ANTENNAS_JOINT_POSITIONS
from reachy_mini_conversation_app.tools.core_tools import Tool, ToolDependencies
from reachy_mini_conversation_app.dance_emotion_moves import GotoQueueMove


logger = logging.getLogger(__name__)


class LowerAntennas(Tool):
    """Fold both antennas down (sleep-like resting position)."""

    name = "lower_antennas"
    description = (
        "Lower both antennas so they are folded down against the head. "
        "Use when the user asks to lower, drop, fold down, or hide the antennas."
    )
    needs_response = False
    parameters_schema = {"type": "object", "properties": {}, "required": []}

    async def __call__(self, deps: ToolDependencies, **kwargs: Any) -> Dict[str, Any]:
        logger.info("Tool call: lower_antennas")
        current_head_pose = deps.reachy_mini.get_current_head_pose()
        head_joints, antenna_joints = deps.reachy_mini.get_current_joint_positions()
        current_body_yaw = float(head_joints[0])
        deps.movement_manager.queue_move(
            GotoQueueMove(
                target_head_pose=current_head_pose,
                start_head_pose=current_head_pose,
                target_antennas=(SLEEP_ANTENNAS_JOINT_POSITIONS[0], SLEEP_ANTENNAS_JOINT_POSITIONS[1]),
                start_antennas=(float(antenna_joints[0]), float(antenna_joints[1])),
                target_body_yaw=current_body_yaw,
                start_body_yaw=current_body_yaw,
                duration=1.5,
            )
        )
        return {"status": "queued", "action": "lower_antennas"}
