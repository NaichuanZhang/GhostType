import json
import websocket
import threading
import time
from testsprite_tests.proxy_connect import proxy_connect

BASE_WS_URL = "ws://localhost:8420/generate"


def test_websocket_generate_streams_tokens_and_completes_successfully():
    ws = None
    received_tokens = []
    done_message = None
    error_occurred = False

    def on_message(wsapp, message):
        nonlocal done_message, error_occurred
        msg = json.loads(message)
        msg_type = msg.get("type")
        if msg_type == "token":
            received_tokens.append(msg.get("content"))
        elif msg_type == "done":
            done_message = msg.get("content")
            wsapp.close()
        elif msg_type == "error":
            error_occurred = True
            wsapp.close()

    def on_error(wsapp, error):
        nonlocal error_occurred
        error_occurred = True

    def on_close(wsapp, close_status_code, close_msg):
        pass

    def on_open(wsapp):
        # Send valid generation request
        request_payload = {
            "prompt": "Hello, how are you?",
            "context": "Previous conversation context.",
            "mode": "generate",
            "mode_type": "draft",
            "config": {
                "provider": "bedrock",
                "model_id": "test-model",
                "aws_profile": "default",
                "aws_region": "us-west-2"
            }
        }
        wsapp.send(json.dumps(request_payload))

    websocket.enableTrace(False)
    ws = websocket.WebSocketApp(
        BASE_WS_URL,
        on_message=on_message,
        on_error=on_error,
        on_close=on_close,
        on_open=on_open,
        **proxy_connect()
    )

    wst = threading.Thread(target=ws.run_forever, kwargs={"ping_interval": 10, "ping_timeout": 5})
    wst.daemon = True
    wst.start()

    timeout = 30
    start_time = time.time()
    while wst.is_alive() and (time.time() - start_time) < timeout:
        if done_message or error_occurred:
            break
        time.sleep(0.1)

    ws.close()

    assert not error_occurred, "Error message received from server"
    assert done_message is not None, "Did not receive done message"
    assert received_tokens, "Did not receive any token messages"
    combined_tokens = "".join(received_tokens)
    # done message content should include the generated text containing the tokens collected
    assert combined_tokens in done_message or done_message in combined_tokens, "Done message content mismatch with tokens"


test_websocket_generate_streams_tokens_and_completes_successfully()