import asyncio
import json
import websockets

async def test_websocket_generate_supports_new_conversation_reset():
    uri = "ws://127.0.0.1:8420/generate"

    async with websockets.connect(uri) as websocket:
        # Send new_conversation message
        await websocket.send(json.dumps({"type": "new_conversation"}))

        # Receive response
        response = await websocket.recv()
        message = json.loads(response)

        # Assert the response type is conversation_reset
        assert isinstance(message, dict), "Response is not a JSON object"
        assert message.get("type") == "conversation_reset", f"Expected type=conversation_reset, got: {message.get('type')}"

asyncio.run(test_websocket_generate_supports_new_conversation_reset())