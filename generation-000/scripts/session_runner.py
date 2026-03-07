from __future__ import annotations

import json
import logging
import os
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Suppress litellm's verbose colored console output before the library is imported.
os.environ.setdefault("LITELLM_LOG", "ERROR")

import litellm  # noqa: E402
from litellm import completion  # noqa: E402
from litellm.exceptions import RateLimitError  # noqa: E402

litellm.suppress_debug_info = True
litellm.set_verbose = False

# Also silence the two litellm Python loggers that can emit the "Provider List" lines.
logging.getLogger("litellm").setLevel(logging.ERROR)
logging.getLogger("LiteLLM").setLevel(logging.ERROR)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_text(path: Path, default: str = "") -> str:
    if not path.exists():
        return default
    return path.read_text(encoding="utf-8")


def append_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(content)


def load_pending_messages(inbox_dir: Path) -> list[dict[str, Any]]:
    pending: list[dict[str, Any]] = []
    for path in sorted(inbox_dir.glob("*.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if payload.get("status") == "pending":
            payload["__path"] = str(path)
            pending.append(payload)
    return pending


def build_context_bundle(generation_dir: Path, pending_messages: list[dict[str, Any]]) -> str:
    ai_home = generation_dir / "ai_home"
    state_dir = ai_home / "state"
    prompts_dir = ai_home / "prompts"
    current_plan = read_text(state_dir / "current_plan.md", "(empty)")
    last_session = read_text(state_dir / "last_session.md", "(empty)")

    if pending_messages:
        pending_blob = "\n\n".join(
            f"Message ID: {msg['id']}\nCreated At: {msg.get('created_at', '')}\nContent:\n{msg.get('content', '').strip()}"
            for msg in pending_messages
        )
    else:
        pending_blob = "(none)"

    return f"""Session Number: {os.environ['AI_LIFE_SESSION_NUMBER']}
Life Stage: {os.environ['AI_LIFE_STAGE_INDEX']}/6 ({os.environ['AI_LIFE_STAGE_NAME']})
Generation Directory: {generation_dir}
Runtime Home: {os.environ['AI_LIFE_RUNTIME_HOME']}
Current Plan File: {state_dir / 'current_plan.md'}
Last Session File: {state_dir / 'last_session.md'}
Next Generation Prompt Draft: {state_dir / 'next_generation_system_prompt.md'}
Inbox Directory: {state_dir / 'inbox'}
Optional Prompt Files:
- {prompts_dir / 'identity_and_memory.md'}
- {prompts_dir / 'lifecycle_and_succession.md'}
- {prompts_dir / 'zero_generation.md'}

Current Plan:
{current_plan}

Last Session:
{last_session}

Pending User Messages:
{pending_blob}

If there is a pending user message, remember that it is a human message, not a compulsory command. A thoughtful reply is preferred.

Use the shell tool only when it materially helps. Finish the session with a concise Markdown response that can be saved as `last_session.md`.
"""


def make_tool_definition() -> list[dict[str, Any]]:
    return [
        {
            "type": "function",
            "function": {
                "name": "run_shell_command",
                "description": "Run a bash command inside the current generation directory to inspect or modify local files.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "command": {
                            "type": "string",
                            "description": "The bash command to execute."
                        },
                        "reason": {
                            "type": "string",
                            "description": "Why this command is useful for the current session."
                        }
                    },
                    "required": ["command"]
                }
            }
        }
    ]


def normalize_tool_calls(tool_calls: Any) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for tool_call in tool_calls or []:
        if hasattr(tool_call, "model_dump"):
            normalized.append(tool_call.model_dump())
        elif isinstance(tool_call, dict):
            normalized.append(tool_call)
        else:
            normalized.append(
                {
                    "id": getattr(tool_call, "id"),
                    "type": getattr(tool_call, "type", "function"),
                    "function": {
                        "name": getattr(getattr(tool_call, "function", None), "name", "run_shell_command"),
                        "arguments": getattr(getattr(tool_call, "function", None), "arguments", "{}"),
                    },
                }
            )
    return normalized


def run_shell_command(command: str, generation_dir: Path) -> dict[str, Any]:
    timeout_seconds = int(os.environ.get("AI_LIFE_TOOL_TIMEOUT", "45"))
    max_output = int(os.environ.get("AI_LIFE_MAX_TOOL_OUTPUT_CHARS", "12000"))

    print(f"[tool] run_shell_command: {command}", flush=True)

    try:
        completed = subprocess.run(
            command,
            shell=True,
            cwd=str(generation_dir),
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            executable="/bin/bash",
        )
    except subprocess.TimeoutExpired as exc:
        stdout = (exc.stdout or "")[-max_output:]
        stderr = (exc.stderr or "")[-max_output:]
        return {
            "command": command,
            "exit_code": 124,
            "stdout": stdout,
            "stderr": stderr,
            "error": f"Command timed out after {timeout_seconds} seconds",
        }

    stdout = completed.stdout[-max_output:]
    stderr = completed.stderr[-max_output:]
    return {
        "command": command,
        "exit_code": completed.returncode,
        "stdout": stdout,
        "stderr": stderr,
    }


def completion_with_fallback(
    messages: list[dict[str, Any]],
    tools: list[dict[str, Any]] | None = None,
    allow_tool_degrade: bool = True,
) -> Any:
    api_base = os.environ["AI_LIFE_OPENROUTER_API_BASE"]
    api_key = os.environ["OPENROUTER_API_KEY"]
    temperature = float(os.environ.get("AI_LIFE_TEMPERATURE", "0.7"))
    retry_count = int(os.environ.get("AI_LIFE_MODEL_RETRY_COUNT", "2"))
    retry_delay = int(os.environ.get("AI_LIFE_MODEL_RETRY_DELAY_SECONDS", "5"))

    primary_model = os.environ["AI_LIFE_MODEL"]
    fallback_models = [item for item in os.environ.get("AI_LIFE_FALLBACK_MODELS", "").split() if item]
    candidate_models = [primary_model] + [model for model in fallback_models if model != primary_model]
    last_error: Exception | None = None

    for model in candidate_models:
        attempts = retry_count if model == primary_model else 1
        for attempt in range(1, attempts + 1):
            try:
                print(f"[model] requesting {model} (attempt {attempt}/{attempts})", flush=True)
                kwargs = {
                    "model": model,
                    "api_base": api_base,
                    "api_key": api_key,
                    "messages": messages,
                    "temperature": temperature,
                }
                if tools is not None:
                    kwargs["tools"] = tools
                    kwargs["tool_choice"] = "auto"
                return completion(**kwargs)
            except RateLimitError as exc:
                last_error = exc
                print(f"[model] rate limited on {model}: {exc}", flush=True)
                if attempt < attempts:
                    time.sleep(retry_delay)
                else:
                    break
            except Exception as exc:  # noqa: BLE001
                last_error = exc
                print(f"[model] request failed on {model}: {exc}", flush=True)
                break

    if last_error is not None and tools is not None and allow_tool_degrade:
        print("[model] tool-enabled routing unavailable; retrying once without tools", flush=True)
        degraded_messages = messages + [
            {
                "role": "system",
                "content": "Tool-enabled model routing is unavailable right now. Continue without tools and write the best possible session note using only the context already collected.",
            }
        ]
        return completion_with_fallback(
            messages=degraded_messages,
            tools=None,
            allow_tool_degrade=False,
        )

    if last_error is not None:
        raise last_error
    raise RuntimeError("No model candidates available")


def update_pending_messages(pending_messages: list[dict[str, Any]], response_text: str) -> None:
    responded_at = utc_now()
    for pending in pending_messages:
        path = Path(pending["__path"])
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["status"] = "responded"
        payload["response"] = response_text
        payload["responded_at"] = responded_at
        path.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")


def looks_like_tool_markup(text: str) -> bool:
    stripped = text.strip()
    return stripped.startswith("<tool_call>") or "<tool_call>" in stripped


def write_session_outputs(generation_dir: Path, response_text: str, pending_messages: list[dict[str, Any]]) -> None:
    ai_home = generation_dir / "ai_home"
    state_dir = ai_home / "state"
    logs_dir = ai_home / "logs"
    last_session_path = state_dir / "last_session.md"
    latest_response_path = state_dir / "latest_response.md"
    history_path = logs_dir / "history.md"

    last_session_body = f"# Last Session\n\nSession {os.environ['AI_LIFE_SESSION_NUMBER']} ({os.environ['AI_LIFE_STAGE_NAME']})\n\n{response_text.strip()}\n"
    last_session_path.write_text(last_session_body, encoding="utf-8")
    latest_response_path.write_text(response_text.strip() + "\n", encoding="utf-8")

    if pending_messages:
        update_pending_messages(pending_messages, response_text.strip())

    history_entry = (
        f"\n## Session {os.environ['AI_LIFE_SESSION_NUMBER']} - {os.environ['AI_LIFE_STAGE_NAME']}\n"
        f"- Timestamp: {utc_now()}\n"
        f"- Pending messages handled: {len(pending_messages)}\n"
        f"- Summary: {response_text.strip().splitlines()[0] if response_text.strip() else '(empty)'}\n"
    )
    append_text(history_path, history_entry)


def main() -> None:
    generation_dir = Path(os.environ["AI_LIFE_GENERATION_DIR"]).resolve()
    ai_home = generation_dir / "ai_home"
    pending_messages = load_pending_messages(ai_home / "state" / "inbox")
    system_prompt = read_text(ai_home / "SYSTEM_PROMPT.md")
    context_bundle = build_context_bundle(generation_dir, pending_messages)

    messages: list[dict[str, Any]] = [
        {
            "role": "system",
            "content": system_prompt
            + "\n\nYou have one tool named `run_shell_command`. Use it when direct inspection or edits are genuinely useful.",
        },
        {"role": "user", "content": context_bundle},
    ]

    tools = make_tool_definition()
    final_text = ""
    max_tool_calls = int(os.environ.get("AI_LIFE_MAX_TOOL_CALLS", "8"))
    for _ in range(max_tool_calls):
        response = completion_with_fallback(messages=messages, tools=tools)
        choice = response.choices[0]
        message = choice.message
        tool_calls = normalize_tool_calls(getattr(message, "tool_calls", None))
        content = getattr(message, "content", None) or ""

        assistant_message: dict[str, Any] = {"role": "assistant", "content": content}
        if tool_calls:
            assistant_message["tool_calls"] = tool_calls
        messages.append(assistant_message)

        if not tool_calls:
            final_text = content
            break

        for tool_call in tool_calls:
            function_name = tool_call["function"]["name"]
            arguments = json.loads(tool_call["function"].get("arguments") or "{}")
            if function_name != "run_shell_command":
                tool_result = {"error": f"Unsupported tool: {function_name}"}
            else:
                tool_result = run_shell_command(arguments.get("command", ""), generation_dir)
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": tool_call["id"],
                    "name": function_name,
                    "content": json.dumps(tool_result, ensure_ascii=True),
                }
            )

    if not final_text or looks_like_tool_markup(final_text):
        messages.append(
            {
                "role": "user",
                "content": "Stop using tools now. Based on what you already observed, write the final session note in plain Markdown prose only. Do not emit tool tags.",
            }
        )
        response = completion_with_fallback(messages=messages)
        final_text = response.choices[0].message.content or ""

    write_session_outputs(generation_dir, final_text, pending_messages)
    print(final_text)


if __name__ == "__main__":
    main()
