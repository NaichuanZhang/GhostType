import json
import websocket

def test_websocket_generate_returns_error_for_invalid_mode():
    url = "ws://127.0.0.1:8420/generate"
    invalid_mode_request = {
        "prompt": "Summarize this text quickly",
        "context": "",
        "mode": "summarize",  # invalid/unsupported mode
        "mode_type": "draft",
        "config": {
            "provider": "bedrock",
            "model_id": "dummy-model-id",
            "aws_profile": "default",
            "aws_region": "us-west-2"
        }
    }

    # Connect directly using websocket
    ws = websocket.create_connection(url)

    try:
        ws.send(json.dumps(invalid_mode_request))

        error_received = False
        while True:
            msg = ws.recv()
            if not msg:
                break
            data = json.loads(msg)
            # The server must respond with type=error and message about invalid mode
            if data.get("type") == "error":
                error_received = True
                error_message = data.get("content", "")
                assert "invalid mode" in error_message.lower() or "unsupported mode" in error_message.lower()
                break
        assert error_received, "Expected error message for invalid mode not received"
    finally:
        ws.close()

test_websocket_generate_returns_error_for_invalid_mode()
