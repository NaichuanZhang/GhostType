import asyncio
import json
import websockets
from testsprite_tests.proxy_connect import proxy_connect

BASE_WS_ENDPOINT = "ws://localhost:8420/generate"
TIMEOUT = 30

async def websocket_generate_builds_messages():
    # Modes to test with optional context and screenshot variations
    test_cases = [
        {"prompt": "Generate some text", "mode": "generate", "mode_type": "draft", "context": "Context for generation"},
        {"prompt": "Rewrite this sentence", "mode": "rewrite", "mode_type": "chat", "context": "Previous turn text"},
        {"prompt": "Fix this code snippet", "mode": "fix", "mode_type": "draft", "screenshot": "YmFzZTY0U2NyZWVu"},  # base64 "base64Screen"
        {"prompt": "Translate to French", "mode": "translate", "mode_type": "chat"}
    ]

    async def handle_case(case):
        config = {
            "provider": "bedrock",
            "model_id": "test-model",
            "aws_profile": "default",
            "aws_region": "us-west-2"
        }
        payload = {
            "prompt": case["prompt"],
            "mode": case["mode"],
            "mode_type": case.get("mode_type", "draft"),
            "config": config
        }
        if "context" in case:
            payload["context"] = case["context"]
        if "screenshot" in case:
            payload["screenshot"] = case["screenshot"]

        async with proxy_connect().connect(BASE_WS_ENDPOINT, ping_interval=None) as websocket:
            await websocket.send(json.dumps(payload))
            token_received = False
            done_received = False
            async for message in websocket:
                data = json.loads(message)
                msg_type = data.get("type")
                # Validate streaming token messages
                if msg_type == "token":
                    assert "content" in data and isinstance(data["content"], str)
                    token_received = True
                elif msg_type == "done":
                    assert "content" in data and isinstance(data["content"], str)
                    done_received = True
                    break
                elif msg_type == "error":
                    # Fail test if error received for these valid modes
                    assert False, f"Error received in mode {case['mode']}: {data.get('content')}"
                else:
                    # Can receive other types but not expected here, no fail
                    pass
            assert token_received, f"No token message received for mode {case['mode']}"
            assert done_received, f"No done message received for mode {case['mode']}"

    # Run all test cases sequentially with timeout
    for case in test_cases:
        await asyncio.wait_for(handle_case(case), timeout=TIMEOUT)

# Run the test
asyncio.get_event_loop().run_until_complete(websocket_generate_builds_messages())