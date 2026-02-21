import websocket
import json
import threading
import time
from testsprite_tests import proxy_connect

BASE_WS_URL = "ws://localhost:8420/generate"

def test_websocket_generate_cancel_without_active_generation_returns_error_or_noop():
    ws = websocket.WebSocket()
    try:
        # Connect to the /generate WebSocket endpoint using proxy_connect for proxy support and handshake
        proxy_connect(ws, BASE_WS_URL)

        # Send a cancel message when no generation is active
        cancel_msg = json.dumps({"type": "cancel"})
        ws.send(cancel_msg)

        # Wait and read response(s)
        # The server should respond with an error or no-op message indicating no active generation to cancel
        # We'll allow multiple messages and look for at least one indicating error or no active generation
        received = False
        timeout = time.time() + 10  # 10 second timeout for receiving message
        while time.time() < timeout:
            try:
                msg = ws.recv()
                if not msg:
                    continue
                data = json.loads(msg)
                # Accept responses with type "error" or others indicating no active generation to cancel
                if "type" not in data:
                    continue
                if data["type"] == "error":
                    # Assert error message mentions no active generation or cancel not possible
                    assert any(s in data.get("content", "").lower() for s in ["no active generation", "nothing to cancel", "cannot cancel"])
                    received = True
                    break
                # Some servers may send a no-op or a specific message type for no active generation
                # We accept any valid message type except cancelled or done here
                elif data["type"] in ("cancelled", "done", "token"):
                    # These types not expected as no generation is active, fail if received
                    assert False, f"Unexpected message type received: {data['type']}"
                else:
                    # No-op or other informative messages accepted to satisfy test
                    received = True
                    break
            except websocket.WebSocketTimeoutException:
                break

        assert received, "Did not receive an error or no-op message response after cancel with no active generation"

    finally:
        ws.close()

test_websocket_generate_cancel_without_active_generation_returns_error_or_noop()