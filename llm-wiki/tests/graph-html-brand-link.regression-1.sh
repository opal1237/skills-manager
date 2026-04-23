#!/bin/bash
# Regression: brand mark should link to project repo and stay keyboard-visible

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRAPH_HTML_BASIC="tests/fixtures/graph-interactive-basic"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_file_contains() {
    local file="$1"
    local text="$2"

    if ! grep -F -- "$text" "$file" > /dev/null; then
        fail "Expected $file to contain: $text"
    fi
}

build_graph_html_fixture() {
    local tmp_dir="$1"
    local output_dir="$tmp_dir/wiki"

    mkdir -p "$output_dir"
    cp "$REPO_ROOT/$GRAPH_HTML_BASIC/wiki/graph-data.json" "$output_dir/graph-data.json"

    bash "$REPO_ROOT/scripts/build-graph-html.sh" \
        "$tmp_dir" > /dev/null 2>&1 \
        || fail "build-graph-html.sh should succeed on basic fixture"
}

test_graph_html_has_brand_repo_link() {
    local tmp_dir html
    tmp_dir="$(mktemp -d)"

    build_graph_html_fixture "$tmp_dir"
    html="$tmp_dir/wiki/knowledge-graph.html"

    assert_file_contains "$html" '<a class="brand__mark" href="https://github.com/sdyckjq-lab/llm-wiki-skill"'
    assert_file_contains "$html" 'target="_blank" rel="noopener"'

    rm -rf "$tmp_dir"
}

test_graph_html_has_brand_focus_visible_style() {
    local tmp_dir html
    tmp_dir="$(mktemp -d)"

    build_graph_html_fixture "$tmp_dir"
    html="$tmp_dir/wiki/knowledge-graph.html"

    assert_file_contains "$html" '.brand__mark:focus-visible {'
    assert_file_contains "$html" '@media (prefers-reduced-motion: reduce) {'

    rm -rf "$tmp_dir"
}

main() {
    test_graph_html_has_brand_repo_link
    test_graph_html_has_brand_focus_visible_style
    echo "PASS: graph HTML brand link regression coverage"
}

main "$@"
