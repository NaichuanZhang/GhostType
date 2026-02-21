import json
import time
import websocket
from testsprite_tests import proxy_connect  # Assuming this helper is available for proxy and connection setup

BASE_WS_URL = "ws://localhost:8420/generate"

def test_websocket_generate_supports_cancellation_of_in_progress_generation():
    ws = None
    try:
        # Connect to the WebSocket using proxy_connect helper for tunnel and proxy support
        ws = proxy_connect(BASE_WS_URL)

        # Send a valid generation request to start streaming tokens
        generation_request = {
            "prompt": "This is a test prompt to start generation.",
            "context": "Testing cancellation during generation.",
            "mode": "generate",
            "mode_type": "draft",
            "config": {
                "provider": "bedrock",
                "model_id": "test-model",
                "aws_profile": "default",
                "aws_region": "us-west-2"
            }
        }
        ws.send(json.dumps(generation_request))

        received_token_messages = 0
        cancelled_received = False

        # Wait for some tokens, then send cancel message
        timeout_at = time.time() + 30  # 30 seconds timeout
        while time.time() < timeout_at:
            raw_msg = ws.recv()
            assert raw_msg is not None, "Received None message from WebSocket"
            msg = json.loads(raw_msg)

            # Accept types: token, done, error, cancelled
            msg_type = msg.get("type")
            assert msg_type in ("token", "done", "error", "cancelled"), f"Unexpected msg type {msg_type}"

            if msg_type == "token":
                received_token_messages += 1
                # After receiving at least 2 tokens, send cancellation
                if received_token_messages == 2:
                    ws.send(json.dumps({"type": "cancel"}))
            elif msg_type == "cancelled":
                cancelled_received = True
                # After cancelled received, break loop as generation should stop
                break
            elif msg_type == "done":
                # If generation finishes without cancel message received, assert fail
                assert False, "Generation completed before cancellation was confirmed"
            elif msg_type == "error":
                # If error received, fail test
                assert False, f"Received error message from server: {msg.get('content')}"
        else:
            # Timeout expired without receiving cancelled message
            assert False, "Timeout expired without receiving cancelled message"

        assert cancelled_received, "Cancelled message was not received after sending cancel"

        # Ensure no further tokens are received after cancellation
        # Wait shortly to see if unexpected tokens come after cancelled
        time.sleep(1)
        # Non-blocking check, if more messages received they would be tokens or otherwise
        try:
            ws.settimeout(1)
            followup_msg = ws.recv()
            followup = json.loads(followup_msg)
            # After cancellation, no token or done messages should be received
            assert followup.get("type") != "token", "Received token after cancellation"
            assert followup.get("type") != "done", "Received done after cancellation"
        except websocket.WebSocketTimeoutException:
            # Expected no messages after cancelled
            pass

    finally:
        if ws:
            ws.close()

test_websocket_generate_supports_cancellation_of_in_progress_generation()