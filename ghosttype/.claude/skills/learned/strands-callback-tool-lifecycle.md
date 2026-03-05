---
name: strands-callback-tool-lifecycle
description: "Track Strands Agent tool call lifecycle via callback handler state, since ToolResultEvent never reaches callbacks"
user-invocable: false
origin: auto-extracted
---

# Strands Agent Callback Tool Lifecycle Tracking

**Extracted:** 2026-03-04
**Context:** GhostType backend StreamingCallbackHandler bridging Strands Agent events to WebSocket

## Problem
Strands Agent's callback handler receives streaming events but NOT all lifecycle events. Specifically:
- `ToolResultEvent` has `is_callback_event = False` — **never dispatched to callbacks**
- `ModelStopReason` with `stop_reason == "tool_use"` also has `is_callback_event = False`

This means you cannot detect tool completion via an explicit "tool done" event.

## Solution
Track tool state in the handler and **infer completion from transitions**:

```python
# In StreamingCallbackHandler.__init__:
self._active_tool_id: str | None = None
self._active_tool_name: str | None = None
self._active_tool_input: dict | None = None
```

### Events that DO reach the callback:

| kwargs key | Meaning |
|-----------|---------|
| `event.contentBlockStart.start.toolUse` | Tool invocation starts — contains `{name, toolUseId}` |
| `current_tool_use` | Tool input streaming — contains `{toolUseId, name, input}` |
| `data` | Text token (existing) |
| `complete` | Stream end (existing) |

### Infer tool_done from these transitions:
1. **Text data arrives** while a tool is active → tool finished, text is the response
2. **New tool starts** while another is active → previous tool finished
3. **Stream completes** while a tool is active → tool finished

```python
def _close_active_tool(self):
    if self._active_tool_id is not None:
        self._send_ws_message({"type": "tool_done", ...})
        self._active_tool_id = None

def __call__(self, **kwargs):
    # 1. Check for tool start
    tool_use = event.get("contentBlockStart", {}).get("start", {}).get("toolUse")
    if tool_use:
        self._close_active_tool()  # close previous if any
        # ... set _active_tool_id, send tool_start
        return  # tool start events don't carry text

    # 2. Accumulate tool input from current_tool_use
    current_tool = kwargs.get("current_tool_use")
    if current_tool and self._active_tool_id:
        self._active_tool_input = current_tool.get("input")

    # 3. Close tool on text arrival or stream complete
    if data and self._active_tool_id:
        self._close_active_tool()
    if complete and self._active_tool_id:
        self._close_active_tool()
```

## When to Use
- Extending StreamingCallbackHandler with new event types
- Adding tool-level metrics (duration, input/output logging)
- Debugging why certain Strands events don't appear in callbacks
