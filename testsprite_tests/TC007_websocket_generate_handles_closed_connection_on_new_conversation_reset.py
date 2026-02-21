import websocket
import json
import pytest
from testsprite_tests import proxy_connect


def test_websocket_generate_handles_closed_connection_on_new_conversation_reset():
    ws_url = "ws://localhost:8420/generate"
    ws = None
    try:
        ws = proxy_connect(ws_url)
        ws.close()
        with pytest.raises((websocket.WebSocketConnectionClosedException, websocket.WebSocketException, OSError)):
            ws.send(json.dumps({"type": "new_conversation"}))
    finally:
        if ws and ws.sock and ws.sock.connected:
            ws.close()


test_websocket_generate_handles_closed_connection_on_new_conversation_reset()