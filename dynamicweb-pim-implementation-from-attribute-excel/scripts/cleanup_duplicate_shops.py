#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tomllib
from pathlib import Path


def load_config(server_name: str, config_path: Path) -> tuple[str, list[str]]:
    if not config_path.exists():
        raise FileNotFoundError(
            f"MCP config file not found: {config_path}. Provide --endpoint and any needed --header values, "
            "or point --config-path to a valid Codex config."
        )
    config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    server = config["mcp_servers"][server_name]
    headers = [f"{key}: {value}" for key, value in server.get("http_headers", {}).items()]
    return server["url"], headers


def resolve_endpoint_and_headers(args: argparse.Namespace) -> tuple[str, list[str]]:
    explicit_headers = list(args.header)
    if args.endpoint:
        return args.endpoint, explicit_headers

    env_endpoint = os.environ.get("DW_MCP_ENDPOINT") or os.environ.get("MCP_ENDPOINT")
    if env_endpoint:
        env_headers = []
        for env_name in ("DW_MCP_HEADERS", "MCP_HEADERS"):
            raw = os.environ.get(env_name)
            if raw:
                env_headers.extend([item.strip() for item in raw.splitlines() if item.strip()])
        return env_endpoint, env_headers + explicit_headers

    endpoint, config_headers = load_config(args.server_name, Path(args.config_path).resolve())
    return endpoint, config_headers + explicit_headers


def parse_helper_payload(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    result = data.get("result")
    if not isinstance(result, dict):
        return result

    structured = result.get("structuredContent")
    if isinstance(structured, dict) and "result" in structured:
        return structured["result"]

    content = result.get("content")
    if isinstance(content, list):
        text_parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text" and item.get("text"):
                text_parts.append(str(item["text"]))
        if len(text_parts) == 1:
            text = text_parts[0]
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                return text
        if text_parts:
            return text_parts

    return result


def run_mcp_call(
    *,
    helper_path: Path,
    endpoint: str,
    headers: list[str],
    tool_name: str,
    arguments_file: Path,
    output_file: Path,
    timeout: int,
) -> object:
    cmd = [
        sys.executable,
        str(helper_path),
        "--endpoint",
        endpoint,
        "--tool-name",
        tool_name,
        "--arguments-file",
        str(arguments_file),
        "--output-file",
        str(output_file),
        "--skip-initialize",
        "--timeout",
        str(timeout),
    ]
    for header in headers:
        cmd.extend(["--header", header])

    completed = subprocess.run(cmd, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"{tool_name} failed with exit code {completed.returncode}")
    return parse_helper_payload(output_file)


def main() -> None:
    parser = argparse.ArgumentParser(description="Delete duplicate same-name PIM shops while keeping one chosen shop id.")
    parser.add_argument("--shop-name", required=True)
    parser.add_argument("--keep-shop-id", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--server-name", default="jfa")
    parser.add_argument("--config-path", default=str(Path.home() / ".codex" / "config.toml"))
    parser.add_argument("--endpoint")
    parser.add_argument("--header", action="append", default=[])
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    helper_path = Path(__file__).with_name("mcp_call.py")
    endpoint, headers = resolve_endpoint_and_headers(args)

    empty_args_path = output_dir / "get_shops_args.json"
    empty_args_path.write_text("{}\n", encoding="utf-8")
    shops = run_mcp_call(
        helper_path=helper_path,
        endpoint=endpoint,
        headers=headers,
        tool_name="get_shops",
        arguments_file=empty_args_path,
        output_file=output_dir / "get_shops_before_cleanup.json",
        timeout=args.timeout,
    )

    matching_shops = [shop for shop in shops if shop.get("name") == args.shop_name]
    delete_ids = [shop["id"] for shop in matching_shops if shop.get("id") != args.keep_shop_id]

    report = {
        "shop_name": args.shop_name,
        "keep_shop_id": args.keep_shop_id,
        "matching_shop_ids": [shop.get("id") for shop in matching_shops],
        "delete_shop_ids": delete_ids,
        "deleted": False,
    }

    if not any(shop.get("id") == args.keep_shop_id for shop in matching_shops):
        raise RuntimeError(
            f"Keep-shop id {args.keep_shop_id!r} was not found among shops named {args.shop_name!r}."
        )

    if args.dry_run or not delete_ids:
        (output_dir / "cleanup_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return

    delete_args_path = output_dir / "delete_shops_args.json"
    delete_args_path.write_text(json.dumps({"shopIds": delete_ids}, ensure_ascii=False, indent=2), encoding="utf-8")
    delete_result = run_mcp_call(
        helper_path=helper_path,
        endpoint=endpoint,
        headers=headers,
        tool_name="delete_shops",
        arguments_file=delete_args_path,
        output_file=output_dir / "delete_shops_result.json",
        timeout=args.timeout,
    )
    report["deleted"] = True
    report["delete_result"] = delete_result
    (output_dir / "cleanup_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
