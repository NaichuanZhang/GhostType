
# TestSprite AI Testing Report(MCP)

---

## 1️⃣ Document Metadata
- **Project Name:** cursor
- **Date:** 2026-02-20
- **Prepared by:** TestSprite AI Team

---

## 2️⃣ Requirement Validation Summary

#### Test TC001 health check api returns server status and model info
- **Test Code:** [TC001_health_check_api_returns_server_status_and_model_info.py](./TC001_health_check_api_returns_server_status_and_model_info.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 20, in <module>
  File "<string>", line 12, in test_health_check_api_returns_server_status_and_model_info
AssertionError: Expected status 'running', got ok

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/c1d53d1b-0c47-4ded-81ac-493f65b33517/8f70c8f2-eb26-4c0f-9a36-1d3e1c29757a
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC002 websocket generate streams tokens and completes successfully
- **Test Code:** [TC002_websocket_generate_streams_tokens_and_completes_successfully.py](./TC002_websocket_generate_streams_tokens_and_completes_successfully.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 2, in <module>
ModuleNotFoundError: No module named 'websocket'

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/c1d53d1b-0c47-4ded-81ac-493f65b33517/edfd90bc-b99e-4458-876f-a9d5e862657c
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC003 websocket generate handles malformed json with error message
- **Test Code:** [TC003_websocket_generate_handles_malformed_json_with_error_message.py](./TC003_websocket_generate_handles_malformed_json_with_error_message.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 1, in <module>
ModuleNotFoundError: No module named 'websocket'

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/c1d53d1b-0c47-4ded-81ac-493f65b33517/29cfe995-63c2-4a16-906a-c3a52b0b7ac5
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC004 websocket generate supports cancellation of in progress generation
- **Test Code:** [TC004_websocket_generate_supports_cancellation_of_in_progress_generation.py](./TC004_websocket_generate_supports_cancellation_of_in_progress_generation.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 3, in <module>
ModuleNotFoundError: No module named 'websocket'

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/c1d53d1b-0c47-4ded-81ac-493f65b33517/9d1798e3-8081-4157-8f36-01f76a649217
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC005 websocket generate cancel without active generation returns error or noop
- **Test Code:** [TC005_websocket_generate_cancel_without_active_generation_returns_error_or_noop.py](./TC005_websocket_generate_cancel_without_active_generation_returns_error_or_noop.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 1, in <module>
ModuleNotFoundError: No module named 'websocket'

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/c1d53d1b-0c47-4ded-81ac-493f65b33517/22fd64bc-87e5-449d-9254-c5f45abe666c
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC006 websocket generate supports new conversation reset
- **Test Code:** [TC006_websocket_generate_supports_new_conversation_reset.py](./TC006_websocket_generate_supports_new_conversation_reset.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 3, in <module>
ModuleNotFoundError: No module named 'websockets'

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/c1d53d1b-0c47-4ded-81ac-493f65b33517/28cecffd-38c8-4795-ba6f-77b1f6efdbe4
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC007 websocket generate handles closed connection on new conversation reset
- **Test Code:** [TC007_websocket_generate_handles_closed_connection_on_new_conversation_reset.py](./TC007_websocket_generate_handles_closed_connection_on_new_conversation_reset.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 1, in <module>
ModuleNotFoundError: No module named 'websocket'

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/c1d53d1b-0c47-4ded-81ac-493f65b33517/343c4c67-eb48-4e48-9c18-2a08a66120d7
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC008 websocket generate builds messages based on mode and context
- **Test Code:** [TC008_websocket_generate_builds_messages_based_on_mode_and_context.py](./TC008_websocket_generate_builds_messages_based_on_mode_and_context.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 3, in <module>
ModuleNotFoundError: No module named 'websockets'

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/c1d53d1b-0c47-4ded-81ac-493f65b33517/19f5dfa8-bc40-4b69-bc49-3039c29e5c2f
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC009 websocket generate returns error for invalid mode
- **Test Code:** [TC009_websocket_generate_returns_error_for_invalid_mode.py](./TC009_websocket_generate_returns_error_for_invalid_mode.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 2, in <module>
ModuleNotFoundError: No module named 'websocket'

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/c1d53d1b-0c47-4ded-81ac-493f65b33517/ae3ca857-9f53-459c-81c3-3b4f70916e8d
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC010 websocket generate supports per request model configuration
- **Test Code:** [TC010_websocket_generate_supports_per_request_model_configuration.py](./TC010_websocket_generate_supports_per_request_model_configuration.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 1, in <module>
ModuleNotFoundError: No module named 'websocket'

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/c1d53d1b-0c47-4ded-81ac-493f65b33517/ef46a721-c439-46e4-a355-95c6ae08a5bb
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---


## 3️⃣ Coverage & Matching Metrics

- **0.00** of tests passed

| Requirement        | Total Tests | ✅ Passed | ❌ Failed  |
|--------------------|-------------|-----------|------------|
| ...                | ...         | ...       | ...        |
---


## 4️⃣ Key Gaps / Risks
{AI_GNERATED_KET_GAPS_AND_RISKS}
---