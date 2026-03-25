#!/usr/bin/env python3
"""Traverse doc.dynamicweb.dev and build a reusable context payload."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse, urlunparse
from urllib.request import Request, urlopen

DEFAULT_ROOT_URL = "https://doc.dynamicweb.dev/index.html"
DEFAULT_SITEMAP_URL = "https://doc.dynamicweb.dev/sitemap.xml"
DEFAULT_INCLUDE_PREFIXES = ["/documentation/", "/manual/", "/api/"]

TEXT_TAGS = {"h1", "h2", "h3", "h4", "h5", "p", "li"}
SIGNAL_TERMS = {
    "dynamicweb",
    "documentation",
    "integration",
    "api",
    "module",
    "product",
    "commerce",
    "order",
    "checkout",
    "content",
    "page",
    "item",
    "field",
    "settings",
    "provider",
    "extension",
    "deployment",
    "security",
}
STOPWORDS = {
    "the",
    "and",
    "for",
    "are",
    "was",
    "were",
    "can",
    "could",
    "should",
    "would",
    "has",
    "had",
    "that",
    "this",
    "with",
    "without",
    "from",
    "into",
    "onto",
    "over",
    "under",
    "after",
    "before",
    "during",
    "within",
    "while",
    "because",
    "between",
    "about",
    "above",
    "below",
    "through",
    "across",
    "other",
    "another",
    "more",
    "most",
    "many",
    "much",
    "very",
    "also",
    "only",
    "just",
    "such",
    "same",
    "each",
    "every",
    "both",
    "either",
    "neither",
    "some",
    "any",
    "all",
    "few",
    "several",
    "first",
    "second",
    "third",
    "here",
    "there",
    "have",
    "having",
    "will",
    "might",
    "must",
    "made",
    "make",
    "your",
    "you",
    "yours",
    "ours",
    "our",
    "their",
    "theirs",
    "they",
    "its",
    "it's",
    "them",
    "we",
    "us",
    "his",
    "her",
    "him",
    "she",
    "he",
    "it",
    "via",
    "per",
    "etc",
    "including",
    "include",
    "includes",
    "using",
    "used",
    "use",
    "user",
    "users",
    "create",
    "created",
    "creating",
    "set",
    "sets",
    "new",
    "old",
    "one",
    "two",
    "three",
    "four",
    "five",
    "six",
    "seven",
    "eight",
    "nine",
    "ten",
    "which",
    "where",
    "when",
    "what",
    "then",
    "than",
    "system",
    "documentation",
    "dynamicweb",
}


class DocsHTMLParser(HTMLParser):
    """Extract page title and text blocks from HTML."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title = ""
        self.blocks: list[dict[str, str]] = []
        self._in_title = False
        self._ignore_depth = 0
        self._active_tag: str | None = None
        self._buffer: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:  # noqa: ARG002
        tag = tag.lower()
        if tag in {"script", "style", "noscript", "svg"}:
            self._ignore_depth += 1
            return
        if self._ignore_depth:
            return
        if tag == "title":
            self._in_title = True
        if tag in TEXT_TAGS:
            self._active_tag = tag
            self._buffer = []

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in {"script", "style", "noscript", "svg"}:
            if self._ignore_depth > 0:
                self._ignore_depth -= 1
            return
        if self._ignore_depth:
            return
        if tag == "title":
            self._in_title = False
        if self._active_tag == tag:
            text = normalize_whitespace("".join(self._buffer))
            if text:
                self.blocks.append({"tag": tag, "text": text})
            self._active_tag = None
            self._buffer = []

    def handle_data(self, data: str) -> None:
        if self._ignore_depth:
            return
        if self._in_title:
            self.title += data
        if self._active_tag:
            self._buffer.append(data)


def normalize_whitespace(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def canonicalize_url(url: str) -> str:
    url = url.strip()
    if not url:
        return ""
    parsed = urlparse(url)
    if not parsed.scheme or not parsed.netloc:
        return ""
    cleaned = parsed._replace(fragment="")
    return urlunparse(cleaned)


def tokenize_query(query: str) -> list[str]:
    terms = [token for token in re.split(r"[^a-z0-9]+", query.lower()) if token]
    return [term for term in terms if len(term) > 1]


def read_url_text(url: str, timeout: int) -> str:
    request = Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (compatible; dynamicweb-doc-context-fetcher/1.0)",
            "Accept": "*/*",
        },
    )
    with urlopen(request, timeout=timeout) as response:  # noqa: S310
        raw = response.read()
        content_type = response.headers.get("Content-Type", "")

    encoding = "utf-8"
    match = re.search(r"charset=([\w-]+)", content_type, flags=re.IGNORECASE)
    if match:
        encoding = match.group(1)

    try:
        return raw.decode(encoding, errors="replace")
    except LookupError:
        return raw.decode("utf-8", errors="replace")


def read_text_file(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def extract_sitemap_urls(xml_text: str) -> list[str]:
    root = ET.fromstring(xml_text.lstrip("\ufeff"))
    urls: list[str] = []
    for element in root.iter():
        if element.tag.endswith("loc") and element.text:
            urls.append(element.text.strip())
    return urls


def get_section_key(url: str) -> str:
    path = urlparse(url).path.strip("/")
    if not path:
        return "root"
    parts = path.split("/")
    if parts[0].lower() == "index.html":
        return "root"
    if parts[0] == "documentation":
        if len(parts) > 1 and not parts[1].endswith(".html"):
            return f"documentation/{parts[1]}"
        return "documentation/general"
    if parts[0] == "manual":
        if len(parts) > 1 and not parts[1].endswith(".html"):
            return f"manual/{parts[1]}"
        return "manual/general"
    if parts[0] == "api":
        return "api"
    return parts[0]


def url_allowed(url: str, include_prefixes: list[str], exclude_prefixes: list[str]) -> bool:
    parsed = urlparse(url)
    if parsed.netloc.lower() != "doc.dynamicweb.dev":
        return False

    path = parsed.path or "/"
    lowered = path.lower()

    if lowered in {"/", "/index.html"}:
        return True

    blocked_suffixes = (".png", ".jpg", ".jpeg", ".gif", ".svg", ".css", ".js", ".ico", ".pdf")
    if lowered.endswith(blocked_suffixes):
        return False

    if include_prefixes and not any(path.startswith(prefix) for prefix in include_prefixes):
        return False

    if any(path.startswith(prefix) for prefix in exclude_prefixes):
        return False

    return True


def url_priority(url: str) -> tuple[int, int, str]:
    path = urlparse(url).path.lower()
    is_index = 0 if path.endswith("/index.html") or path == "/index.html" else 1
    depth = len([part for part in path.split("/") if part])
    return (is_index, depth, path)


def group_urls_by_section(urls: list[str]) -> dict[str, list[str]]:
    groups: dict[str, list[str]] = defaultdict(list)
    for url in sorted(urls, key=url_priority):
        groups[get_section_key(url)].append(url)
    return dict(groups)


def select_balanced_urls(
    urls: list[str],
    root_url: str,
    max_pages: int,
    max_pages_per_section: int,
) -> list[str]:
    groups = group_urls_by_section(urls)
    selected: list[str] = []
    selected_set: set[str] = set()
    section_counts: Counter[str] = Counter()

    if root_url in urls:
        selected.append(root_url)
        selected_set.add(root_url)
        section = get_section_key(root_url)
        section_counts[section] += 1
        if section in groups:
            groups[section] = [item for item in groups[section] if item != root_url]

    total_limit = len(urls) if max_pages <= 0 else max_pages
    section_order = sorted(groups.keys(), key=lambda key: (-len(groups[key]), key))

    while len(selected) < total_limit:
        made_progress = False

        for section in section_order:
            if len(selected) >= total_limit:
                break
            if max_pages_per_section > 0 and section_counts[section] >= max_pages_per_section:
                continue
            if not groups.get(section):
                continue

            candidate = groups[section].pop(0)
            if candidate in selected_set:
                continue

            selected.append(candidate)
            selected_set.add(candidate)
            section_counts[section] += 1
            made_progress = True

        if not made_progress:
            break

    return selected


def is_noise_block(text: str, tag: str) -> bool:
    lower = text.lower()
    if not re.search(r"[a-z]", lower):
        return True
    if lower in {"toggle navigation", "navigation", "documentation", "search"}:
        return True
    if len(text) < 4:
        return True
    if tag in {"p", "li"} and len(text) < 30:
        return True
    return False


def score_block(text: str, tag: str, position: int, query_terms: list[str]) -> int:
    lower = text.lower()
    score = 0

    for term in query_terms:
        count = lower.count(term)
        if count:
            score += count * 8

    for term in SIGNAL_TERMS:
        if term in lower:
            score += 1

    if tag.startswith("h"):
        score += 2
    if position < 12:
        score += 2
    if len(text) > 120:
        score += 1

    return score


def trim_text(text: str, max_chars: int = 420) -> str:
    cleaned = normalize_whitespace(text)
    if len(cleaned) <= max_chars:
        return cleaned
    return cleaned[: max_chars - 3].rstrip() + "..."


def extract_snippets(
    blocks: list[dict[str, str]],
    query_terms: list[str],
    max_snippets: int,
) -> list[dict[str, object]]:
    ranked: list[dict[str, object]] = []
    seen: set[str] = set()

    for index, block in enumerate(blocks):
        text = block["text"]
        tag = block["tag"]
        if is_noise_block(text, tag):
            continue

        key = text.lower()
        if key in seen:
            continue
        seen.add(key)

        score = score_block(text, tag, index, query_terms)
        if not query_terms and score == 0:
            score = 1
        if score <= 0:
            continue

        ranked.append(
            {
                "index": index,
                "score": score,
                "tag": tag,
                "text": trim_text(text),
            }
        )

    if not ranked:
        fallback = []
        for index, block in enumerate(blocks):
            text = block["text"]
            tag = block["tag"]
            if is_noise_block(text, tag):
                continue
            fallback.append(
                {
                    "index": index,
                    "score": 0,
                    "tag": tag,
                    "text": trim_text(text),
                }
            )
        ranked = fallback

    ranked = sorted(ranked, key=lambda item: (-int(item["score"]), int(item["index"])))

    output: list[dict[str, object]] = []
    for item in ranked[:max_snippets]:
        output.append(
            {
                "score": int(item["score"]),
                "tag": str(item["tag"]),
                "text": str(item["text"]),
            }
        )
    return output


def extract_terms(text: str) -> list[str]:
    terms = re.findall(r"[a-z][a-z0-9-]{2,}", text.lower())
    return [term for term in terms if term not in STOPWORDS and not term.isdigit()]


def parse_page_to_result(url: str, html: str, query_terms: list[str], max_snippets: int) -> dict[str, object]:
    parser = DocsHTMLParser()
    parser.feed(html)
    parser.close()

    title = normalize_whitespace(parser.title) or url
    snippets = extract_snippets(parser.blocks, query_terms, max_snippets)

    return {
        "url": url,
        "section": get_section_key(url),
        "title": title,
        "snippet_count": len(snippets),
        "snippets": snippets,
    }


def build_section_rows(
    discovered_urls: list[str],
    selected_urls: list[str],
    groups: dict[str, list[str]],
) -> list[dict[str, object]]:
    discovered_counts: Counter[str] = Counter(get_section_key(url) for url in discovered_urls)
    selected_counts: Counter[str] = Counter(get_section_key(url) for url in selected_urls)

    section_rows: list[dict[str, object]] = []
    for section, discovered in discovered_counts.most_common():
        sample_urls = groups.get(section, [])[:3]
        section_rows.append(
            {
                "section": section,
                "discovered": discovered,
                "selected": selected_counts.get(section, 0),
                "sample_urls": sample_urls,
            }
        )

    return section_rows


def main() -> int:
    parser = argparse.ArgumentParser(description="Traverse Dynamicweb docs and build context")
    parser.add_argument("--root-url", default=DEFAULT_ROOT_URL, help="Site root URL to prioritize")
    parser.add_argument("--sitemap-url", default=DEFAULT_SITEMAP_URL, help="Sitemap URL for global discovery")
    parser.add_argument("--sitemap-file", help="Local sitemap XML file (used instead of --sitemap-url)")
    parser.add_argument("--query", default="", help="Optional focus query for snippet ranking")
    parser.add_argument("--include-prefix", action="append", default=[], help="Path prefix to include (repeatable)")
    parser.add_argument("--exclude-prefix", action="append", default=[], help="Path prefix to exclude (repeatable)")
    parser.add_argument("--all-prefixes", action="store_true", help="Include all sitemap paths on doc.dynamicweb.dev")
    parser.add_argument("--max-pages", type=int, default=140, help="Max number of pages to fetch; <=0 means all")
    parser.add_argument(
        "--max-pages-per-section",
        type=int,
        default=25,
        help="Max fetched pages per section; <=0 disables section cap",
    )
    parser.add_argument("--max-snippets-per-page", type=int, default=4, help="Max snippets extracted per page")
    parser.add_argument("--max-top-terms", type=int, default=40, help="Max terms in top_terms output")
    parser.add_argument("--timeout", type=int, default=20, help="HTTP timeout seconds")
    parser.add_argument("--inventory-only", action="store_true", help="Only build URL inventory; do not fetch pages")
    parser.add_argument("--output", help="Output JSON file path (stdout when omitted)")
    args = parser.parse_args()

    root_url = canonicalize_url(args.root_url)
    if not root_url:
        print("Invalid --root-url.", file=sys.stderr)
        return 1

    include_prefixes = [] if args.all_prefixes else (args.include_prefix or DEFAULT_INCLUDE_PREFIXES)
    exclude_prefixes = args.exclude_prefix or []

    try:
        if args.sitemap_file:
            sitemap_source = str(Path(args.sitemap_file).resolve())
            sitemap_xml = read_text_file(Path(args.sitemap_file).resolve())
        else:
            sitemap_source = args.sitemap_url
            sitemap_xml = read_url_text(args.sitemap_url, args.timeout)
    except Exception as exc:  # noqa: BLE001
        print(f"Failed to load sitemap: {exc}", file=sys.stderr)
        return 1

    try:
        raw_urls = extract_sitemap_urls(sitemap_xml)
    except Exception as exc:  # noqa: BLE001
        print(f"Failed to parse sitemap XML: {exc}", file=sys.stderr)
        return 1

    discovered_urls: list[str] = []
    seen: set[str] = set()

    for raw_url in raw_urls:
        url = canonicalize_url(raw_url)
        if not url or url in seen:
            continue
        if not url_allowed(url, include_prefixes, exclude_prefixes):
            continue
        discovered_urls.append(url)
        seen.add(url)

    if url_allowed(root_url, include_prefixes, exclude_prefixes) and root_url not in seen:
        discovered_urls.insert(0, root_url)

    if not discovered_urls:
        print("No URLs matched the include/exclude filters.", file=sys.stderr)
        return 1

    selected_urls = select_balanced_urls(
        discovered_urls,
        root_url=root_url,
        max_pages=args.max_pages,
        max_pages_per_section=args.max_pages_per_section,
    )

    grouped_discovered = group_urls_by_section(discovered_urls)
    section_rows = build_section_rows(discovered_urls, selected_urls, grouped_discovered)

    query_terms = tokenize_query(args.query)
    term_counter: Counter[str] = Counter()
    results: list[dict[str, object]] = []
    fetched_success = 0

    if not args.inventory_only:
        for url in selected_urls:
            try:
                html = read_url_text(url, timeout=args.timeout)
                result = parse_page_to_result(url, html, query_terms, args.max_snippets_per_page)
                for snippet in result.get("snippets", []):
                    if not isinstance(snippet, dict):
                        continue
                    for term in extract_terms(str(snippet.get("text", ""))):
                        term_counter[term] += 1
                results.append(result)
                fetched_success += 1
            except Exception as exc:  # noqa: BLE001
                results.append(
                    {
                        "url": url,
                        "section": get_section_key(url),
                        "title": url,
                        "snippet_count": 0,
                        "snippets": [],
                        "error": str(exc),
                    }
                )

    payload = {
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "query": args.query,
        "query_terms": query_terms,
        "crawl": {
            "root_url": root_url,
            "sitemap_source": sitemap_source,
            "inventory_only": args.inventory_only,
            "include_prefixes": include_prefixes,
            "exclude_prefixes": exclude_prefixes,
            "max_pages": args.max_pages,
            "max_pages_per_section": args.max_pages_per_section,
            "discovered_url_count": len(discovered_urls),
            "selected_url_count": len(selected_urls),
            "fetched_success_count": fetched_success,
        },
        "sections": section_rows,
        "top_terms": [{"term": term, "count": count} for term, count in term_counter.most_common(args.max_top_terms)],
        "results": results,
    }

    output_json = json.dumps(payload, indent=2, ensure_ascii=True)
    if args.output:
        output_path = Path(args.output)
        output_path.write_text(output_json + "\n", encoding="utf-8")
        print(f"Wrote context payload to {output_path}")
    else:
        print(output_json)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
