import websocket
import json
import pytest
from testsprite_tests.proxy_connect import proxy_connect


def test_websocket_generate_per_request_model_configuration():
    ws_url = "ws://localhost:8420/generate"
    # Prepare the request with per-request model config
    request_payload = {
        "prompt": "Hello, please generate text with specified model.",
        "context": "Test context for per-request model config",
        "mode": "generate",
        "mode_type": "draft",
        "config": {
            "provider": "bedrock",
            "model_id": "test-model-123",
            "aws_profile": "default",
            "aws_region": "us-west-2"
        }
    }

    messages = []

    def on_message(ws, message):
        msg = json.loads(message)
        messages.append(msg)

    def on_error(ws, error):
        pytest.fail(f"WebSocket error: {error}")

    def on_close(ws, close_status_code, close_msg):
        pass  # No action needed on close

    def on_open(ws):
        ws.send(json.dumps(request_payload))

    # Connect to websocket using proxy_connect helper for HTTP_PROXY tunnels if needed
    ws = websocket.WebSocketApp(
        ws_url,
        on_open=on_open,
        on_message=on_message,
        on_error=on_error,
        on_close=on_close,
    )

    # Run the websocket client in proxy_connect context to support proxy if configured
    with proxy_connect(ws):
        # Timeout and run forever until closed or done message received
        # We'll close connection once done message is received to finish test early
        def run_forever_with_done_check():
            while True:
                ws.run_forever(timeout=30, ping_interval=10, ping_timeout=5)
                # Check for done message to exit
                if any(msg.get("type") == "done" for msg in messages):
                    break
                # If error message received, fail the test
                if any(msg.get("type") == "error" for msg in messages):
                    error_msg = next(
                        msg.get("content") for msg in messages if msg.get("type") == "error"
                    )
                    pytest.fail(f"Server returned error: {error_msg}")

        run_forever_with_done_check()

    # Assertions after websocket is closed
    assert len(messages) > 0, "No messages received from server"
    # Expect at least one token message and one done message
    token_msgs = [m for m in messages if m.get("type") == "token"]
    done_msgs = [m for m in messages if m.get("type") == "done"]
    error_msgs = [m for m in messages if m.get("type") == "error"]
    cancelled_msgs = [m for m in messages if m.get("type") == "cancelled"]

    assert len(error_msgs) == 0, f"Unexpected error messages: {error_msgs}"
    assert len(cancelled_msgs) == 0, f"Unexpected cancelled messages: {cancelled_msgs}"
    assert len(token_msgs) > 0, "No token messages received"
    assert len(done_msgs) == 1, "Expected exactly one done message"

    # Validate done message contains expected keys and a finished generated text content
    done_msg = done_msgs[0]
    assert "content" in done_msg and isinstance(done_msg["content"], str)
    assert done_msg["content"], "Done message content is empty"
    # Validate streamed token contents concatenate to done content start (basic consistency)
    token_content = "".join(m.get("content", "") for m in token_msgs)
    assert done_msg["content"].startswith(token_content[: len(done_msg["content"])])


test_websocket_generate_per_request_model_configuration()