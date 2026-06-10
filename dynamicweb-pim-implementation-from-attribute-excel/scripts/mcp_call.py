#!/usr/bin/env python3
"""
mcp_call.py - Send large MCP requests from files to an MCP endpoint.
"""

import argparse
import json
import ssl
import sys
import uuid
import urllib.error
import urllib.request
from typing import Any

try:
    from jsonschema import Draft202012Validator
except ModuleNotFoundError:
    Draft202012Validator = None


def load_json_file(filepath: str, label: str) -> dict:
    try:
        with open(filepath, "r", encoding="utf-8-sig") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        print(f"ERROR: {label} file not found: {filepath}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as exc:
        print(f"ERROR: Invalid JSON in {filepath}: {exc}", file=sys.stderr)
        sys.exit(1)

    return data


def describe_json(label: str, data: dict) -> None:
    size_bytes = len(json.dumps(data).encode("utf-8"))
    print(f"{label} loaded: {size_bytes:,} bytes", file=sys.stderr)

    if isinstance(data, dict):
        for key, value in data.items():
            if isinstance(value, list):
                print(f"  {key}: {len(value)} items", file=sys.stderr)


def build_tools_call_request(tool_name: str, arguments: dict, request_id: str, progress_token: str | None = None) -> dict:
    params: dict[str, Any] = {
        "name": tool_name,
        "arguments": arguments,
    }
    if progress_token is not None:
        params["_meta"] = {"progressToken": progress_token}
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": "tools/call",
        "params": params,
    }


def parse_headers(header_values: list[str]) -> dict[str, str]:
    headers: dict[str, str] = {}
    for value in header_values:
        if ":" not in value:
            print(f"ERROR: Invalid header format: {value}", file=sys.stderr)
            sys.exit(1)
        key, header_value = value.split(":", 1)
        headers[key.strip()] = header_value.strip()
    return headers


def extract_sse_json(response_body: str) -> Any:
    data_lines = []
    for line in response_body.splitlines():
        if line.startswith("data:"):
            data_lines.append(line[5:].strip())

    if not data_lines:
        return json.loads(response_body)

    for payload in data_lines:
        if not payload:
            continue
        parsed = json.loads(payload)
        if isinstance(parsed, dict) and parsed.get("error"):
            return parsed
        if isinstance(parsed, dict) and parsed.get("result") is not None:
            return parsed

    return json.loads(data_lines[-1])


def format_json_path(path_parts: list[Any]) -> str:
    path = "$"
    for part in path_parts:
        if isinstance(part, int):
            path += f"[{part}]"
        else:
            path += f".{part}"
    return path


def emit(message: str, *, log_handle=None) -> None:
    print(message, file=sys.stderr, flush=True)
    if log_handle is not None:
        print(message, file=log_handle, flush=True)


def write_output_file(path: str, content: str) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)


def extract_tool_error(parsed: Any) -> str | None:
    if not isinstance(parsed, dict):
        return None

    error = parsed.get("error")
    if isinstance(error, dict):
        message = error.get("message")
        if message:
            return str(message)

    result = parsed.get("result")
    if not isinstance(result, dict) or not result.get("isError"):
        return None

    content = result.get("content")
    if isinstance(content, list):
        messages = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text" and item.get("text"):
                messages.append(str(item["text"]))
        if messages:
            return " ".join(messages)

    return "Tool returned isError=true."


def send_request(
    endpoint: str,
    request_body: dict,
    headers: dict[str, str],
    timeout: int = 60,
    method: str = "POST",
    stream_progress: bool = False,
    log_handle=None,
) -> tuple[int, dict[str, str], str]:
    body = json.dumps(request_body).encode("utf-8")

    req = urllib.request.Request(
        endpoint,
        data=body,
        headers=headers,
        method=method,
    )
    ssl_context = ssl._create_unverified_context()

    try:
        with urllib.request.urlopen(req, context=ssl_context, timeout=timeout) as response:
            status = response.status
            response_headers = dict(response.headers)
            emit(f"HTTP {status}", log_handle=log_handle)

            if stream_progress:
                lines: list[str] = []
                for raw_line in response:
                    line = raw_line.decode("utf-8").rstrip("\r\n")
                    lines.append(line)
                    if not line.startswith("data:"):
                        continue
                    payload = line[5:].strip()
                    if not payload:
                        continue
                    try:
                        event = json.loads(payload)
                    except json.JSONDecodeError:
                        continue
                    if isinstance(event, dict) and event.get("method") == "notifications/progress":
                        params = event.get("params", {})
                        current = params.get("progress")
                        total = params.get("total")
                        msg = params.get("message", "")
                        if msg:
                            if current is not None and total:
                                emit(f"  [{current}/{total}] {msg}", log_handle=log_handle)
                            else:
                                emit(f"  {msg}", log_handle=log_handle)
                response_body = "\n".join(lines)
            else:
                response_body = response.read().decode("utf-8")

            return status, response_headers, response_body

    except urllib.error.HTTPError as exc:
        emit(f"HTTP ERROR {exc.code}: {exc.reason}", log_handle=log_handle)
        error_body = exc.read().decode("utf-8", errors="replace")
        emit(error_body, log_handle=log_handle)
        sys.exit(1)
    except urllib.error.URLError as exc:
        emit(f"CONNECTION ERROR: {exc.reason}", log_handle=log_handle)
        sys.exit(1)
    except TimeoutError:
        emit(f"TIMEOUT: Request exceeded {timeout}s", log_handle=log_handle)
        sys.exit(1)


def initialize_session(endpoint: str, headers: dict[str, str], timeout: int, log_handle=None) -> str | None:
    initialize_request = {
        "jsonrpc": "2.0",
        "id": "init-001",
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "clientInfo": {
                "name": "large-mcp-payload",
                "version": "1.0",
            },
        },
    }

    _, response_headers, response_body = send_request(
        endpoint,
        initialize_request,
        headers,
        timeout=timeout,
        log_handle=log_handle,
    )

    session_id = response_headers.get("Mcp-Session-Id") or response_headers.get("MCP-Session-Id")
    if not session_id:
        emit("Initialize response did not include Mcp-Session-Id; continuing without session header.", log_handle=log_handle)
        emit(response_body, log_handle=log_handle)
        return None

    initialized_headers = dict(headers)
    initialized_headers["Mcp-Session-Id"] = session_id

    send_request(
        endpoint,
        {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
        initialized_headers,
        timeout=timeout,
        log_handle=log_handle,
    )

    return session_id


def fetch_tool_schema(endpoint: str, headers: dict[str, str], timeout: int, tool_name: str, log_handle=None) -> dict[str, Any]:
    _, _, response_body = send_request(
        endpoint,
        {"jsonrpc": "2.0", "id": "tools-list-001", "method": "tools/list", "params": {}},
        headers,
        timeout=timeout,
        log_handle=log_handle,
    )
    parsed = extract_sse_json(response_body)
    tools = parsed.get("result", {}).get("tools", [])
    for tool in tools:
        if tool.get("name") == tool_name:
            return tool.get("inputSchema", {})

    emit(f"ERROR: Tool '{tool_name}' was not found in tools/list.", log_handle=log_handle)
    sys.exit(1)


def validate_arguments(arguments: dict[str, Any], input_schema: dict[str, Any], tool_name: str) -> None:
    if Draft202012Validator is None:
        print("WARNING: jsonschema is not installed; skipping inputSchema validation.", file=sys.stderr)
        return

    if not input_schema:
        print(f"WARNING: Tool '{tool_name}' did not provide an inputSchema; skipping validation.", file=sys.stderr)
        return

    validator = Draft202012Validator(input_schema)
    errors = sorted(validator.iter_errors(arguments), key=lambda error: list(error.path))
    if not errors:
        print(f"Arguments validated against inputSchema for '{tool_name}'.", file=sys.stderr)
        return

    first_error = errors[0]
    print(f"ERROR: Arguments for '{tool_name}' do not match the tool inputSchema.", file=sys.stderr)
    print(f"Path: {format_json_path(list(first_error.path))}", file=sys.stderr)
    print(f"Message: {first_error.message}", file=sys.stderr)
    sys.exit(1)


def main():
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)

    parser = argparse.ArgumentParser(description="Send a large MCP JSON-RPC request to an MCP endpoint from a file.")
    parser.add_argument("--endpoint", required=True, help="MCP endpoint URL")
    parser.add_argument("--tool-name", help="MCP tool name to call. Requires --arguments-file.")
    parser.add_argument("--arguments-file", help="Path to a JSON file containing the tool arguments object.")
    parser.add_argument("--request-file", help="Path to a JSON file containing a full JSON-RPC request body.")
    parser.add_argument("--request-id", default="req-001", help="JSON-RPC request id when constructing a tools/call envelope.")
    parser.add_argument("--timeout", type=int, default=60, help="HTTP timeout in seconds (default: 60)")
    parser.add_argument("--method", default="POST", help="HTTP method (default: POST)")
    parser.add_argument("--header", action="append", default=[], help="Additional HTTP header in 'Name: Value' format.")
    parser.add_argument("--skip-initialize", action="store_true", help="Skip the MCP initialize handshake.")
    parser.add_argument("--progress", action="store_true", help="Request progress notifications from the server.")
    parser.add_argument("--log-file", help="Optional path to append runtime status and progress lines.")
    parser.add_argument("--output-file", help="Optional path to write the final response body as UTF-8 JSON/text.")
    parser.add_argument("--allow-result-error", action="store_true", help="Return exit code 0 even when MCP response contains tool error.")
    args = parser.parse_args()

    log_handle = open(args.log_file, "a", encoding="utf-8") if args.log_file else None
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    headers.update(parse_headers(args.header))

    if args.request_file:
        if args.tool_name or args.arguments_file:
            print("ERROR: Use either --request-file or the pair --tool-name and --arguments-file.", file=sys.stderr)
            sys.exit(1)
        request_body = load_json_file(args.request_file, "Request")
        describe_json("Request", request_body)
    else:
        if not args.tool_name or not args.arguments_file:
            print("ERROR: --tool-name and --arguments-file must be provided together.", file=sys.stderr)
            sys.exit(1)
        arguments = load_json_file(args.arguments_file, "Arguments")
        describe_json("Arguments", arguments)
        progress_token = str(uuid.uuid4()) if args.progress else None
        if progress_token:
            emit(f"Progress token: {progress_token}", log_handle=log_handle)
        request_body = build_tools_call_request(args.tool_name, arguments, args.request_id, progress_token)
        describe_json("Wrapped request", request_body)

    if not args.skip_initialize:
        session_id = initialize_session(args.endpoint, headers, args.timeout, log_handle=log_handle)
        if session_id:
            headers["Mcp-Session-Id"] = session_id
            emit(f"Session initialized: {session_id}", log_handle=log_handle)

    if args.tool_name and args.arguments_file:
        input_schema = fetch_tool_schema(args.endpoint, headers, args.timeout, args.tool_name, log_handle=log_handle)
        validate_arguments(arguments, input_schema, args.tool_name)

    stream = args.progress and not args.request_file
    _, _, response_body = send_request(
        args.endpoint,
        request_body,
        headers,
        timeout=args.timeout,
        method=args.method,
        stream_progress=stream,
        log_handle=log_handle,
    )

    try:
        parsed = extract_sse_json(response_body)
        serialized = json.dumps(parsed, indent=2, ensure_ascii=False)
        if args.output_file:
            write_output_file(args.output_file, serialized + "\n")
        print(serialized)
        tool_error = extract_tool_error(parsed)
        if tool_error:
            emit(f"TOOL ERROR: {tool_error}", log_handle=log_handle)
            if not args.allow_result_error:
                sys.exit(1)
    except json.JSONDecodeError:
        if args.output_file:
            write_output_file(args.output_file, response_body)
        print(response_body)
    finally:
        if log_handle is not None:
            log_handle.close()


if __name__ == "__main__":
    main()
