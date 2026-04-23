#!/bin/bash
# Regression: toolbar buttons should show labels on wide screens and keep tooltip fallback hooks

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

test_graph_html_has_labeled_toolbar_buttons() {
    local tmp_dir html
    tmp_dir="$(mktemp -d)"

    build_graph_html_fixture "$tmp_dir"
    html="$tmp_dir/wiki/knowledge-graph.html"

    assert_file_contains "$html" 'class="iconbtn iconbtn--labeled" id="btn-refit"'
    assert_file_contains "$html" '<span class="iconbtn__text">重排</span>'
    assert_file_contains "$html" '<span class="iconbtn__text">居中</span>'
    assert_file_contains "$html" '<span class="iconbtn__text">设置</span>'

    rm -rf "$tmp_dir"
}

test_graph_html_has_toolbar_tooltip_css() {
    local tmp_dir html
    tmp_dir="$(mktemp -d)"

    build_graph_html_fixture "$tmp_dir"
    html="$tmp_dir/wiki/knowledge-graph.html"

    assert_file_contains "$html" '.iconbtn--labeled {'
    assert_file_contains "$html" '[data-tip]:hover::after,'
    assert_file_contains "$html" '@media (max-width: 900px) {'
    assert_file_contains "$html" '.iconbtn__text { display: none; }'

    rm -rf "$tmp_dir"
}

main() {
    test_graph_html_has_labeled_toolbar_buttons
    test_graph_html_has_toolbar_tooltip_css
    echo "PASS: graph HTML toolbar label regression coverage"
}

main "$@"
