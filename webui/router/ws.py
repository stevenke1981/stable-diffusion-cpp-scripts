"""WebSocket endpoint for real-time log streaming."""
import asyncio
import json
from pathlib import Path

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from webui.generator import get_job, current_job

router = APIRouter()


@router.websocket("/ws/{job_id}")
async def ws_job(websocket: WebSocket, job_id: str):
    await websocket.accept()

    job = get_job(job_id)
    if job is None:
        await websocket.send_text(json.dumps({"type": "error", "message": "Job not found"}))
        await websocket.close()
        return

    # replay buffered lines
    for line in job.lines:
        await websocket.send_text(json.dumps({"type": "log", "line": line}))

    if job.status in ("done", "error", "cancelled"):
        if job.status == "done":
            await websocket.send_text(json.dumps({
                "type": "done",
                "outputs": [f"/outputs/{Path(p).name}" for p in job.outputs],
                "seed": job.params.get("resolved_seed", -1),
            }))
        else:
            await websocket.send_text(json.dumps({"type": "error", "message": job.error or job.status}))
        await websocket.close()
        return

    q = job.subscribe()
    try:
        while True:
            try:
                msg = await asyncio.wait_for(q.get(), timeout=30)
                await websocket.send_text(msg)
                data = json.loads(msg)
                if data.get("type") in ("done", "error"):
                    break
            except asyncio.TimeoutError:
                # send ping to keep alive
                await websocket.send_text(json.dumps({"type": "ping"}))
    except (WebSocketDisconnect, Exception):
        pass
    finally:
        job.unsubscribe(q)
    await websocket.close()
