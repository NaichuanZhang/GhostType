import websocket
import json
import time
from testsprite_tests.proxy_helpers import proxy_connect


def test_websocket_generate_handles_malformed_json_with_error_message():
    url = "ws://localhost:8420/generate"
    ws = None
    try:
        ws = proxy_connect(url, timeout=30)

        # 1. Send malformed JSON (invalid syntax)
        ws.send('{"prompt": "Hello world",,,,}')  # malformed on purpose

        # Expect to receive an error message indicating parse error
        msg = ws.recv()
        msg_data = json.loads(msg)
        assert "type" in msg_data and msg_data["type"] == "error"
        assert (
            "error" in msg_data.get("content", "").lower()
            or "parse" in msg_data.get("content", "").lower()
            or "validation" in msg_data.get("content", "").lower()
        )
        
        # 2. Send JSON missing required 'prompt' field
        invalid_payload = {
            "context": "some context",
            "mode": "generate",
            "mode_type": "draft",
            "config": {
                "provider": "bedrock",
                "model_id": "dummy-model",
                "aws_profile": "dummy-profile",
                "aws_region": "dummy-region",
            },
        }
        ws.send(json.dumps(invalid_payload))

        # Expect to receive error message indicating validation error for missing prompt
        msg2 = ws.recv()
        msg_data2 = json.loads(msg2)
        assert "type" in msg_data2 and msg_data2["type"] == "error"
        assert (
            "prompt" in msg_data2.get("content", "").lower()
            or "required" in msg_data2.get("content", "").lower()
            or "validation" in msg_data2.get("content", "").lower()
        )

    finally:
        if ws:
            ws.close()


test_websocket_generate_handles_malformed_json_with_error_message()
