#!/bin/bash
# NYU DTCC VIP Final Project - SBOM Generator with Dynamic Dependencies
# Captures both static (Syft) and runtime (dtruss) dependencies

set -e

TARGET=""
OUTPUT_DIR="sbom-output"
EXECUTE=false
TIMEOUT=10

usage() {
    cat << EOF
Usage: $0 -t TARGET [-e] [-o DIR]

Generate SBOM with dynamic dependencies

OPTIONS:
    -t    Target binary to analyze
    -e    Execute binary to capture runtime deps (requires sudo)
    -o    Output directory (default: sbom-output)
    -h    Show help

EXAMPLE:
    $0 -t /bin/ls -o results
    sudo $0 -t /usr/bin/curl -e
EOF
    exit 0
}

# Parse arguments
while getopts "t:eo:h" opt; do
    case $opt in
        t) TARGET="$OPTARG" ;;
        e) EXECUTE=true ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

[[ -z "$TARGET" ]] && { echo "Error: No target specified"; usage; }
[[ -f "$TARGET" ]] || { echo "Error: File not found: $TARGET"; exit 1; }

# Check dependencies
command -v syft >/dev/null || { echo "Error: syft not installed"; exit 1; }
command -v jq >/dev/null || { echo "Error: jq not installed"; exit 1; }

mkdir -p "$OUTPUT_DIR"

STATIC_SBOM="$OUTPUT_DIR/initial-sbom.json"
DYNAMIC_LIBS="$OUTPUT_DIR/dynamic-deps.json"
FINAL_SBOM="$OUTPUT_DIR/final-sbom.json"

echo "=== Step 1: Generate base SBOM with Syft ==="
syft "$TARGET" -o json > "$STATIC_SBOM"
echo "✓ Created: $STATIC_SBOM"

echo ""
echo "=== Step 2: Extract linked libraries with otool ==="
otool -L "$TARGET" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v ":" | \
while read lib; do
    [[ -n "$lib" ]] && echo "{\"name\":\"$(basename "$lib")\",\"path\":\"$lib\",\"source\":\"otool\"}"
done | jq -s '.' > "$DYNAMIC_LIBS"

echo "✓ Found $(jq 'length' "$DYNAMIC_LIBS") linked libraries"

# Runtime capture if requested
if [ "$EXECUTE" = true ]; then
    echo ""
    echo "=== Step 3: Capture runtime dependencies with dtruss ==="
    
    TRACE_LOG="$OUTPUT_DIR/dtruss.log"
    
    if [ "$EUID" -ne 0 ]; then
        echo "Warning: Runtime capture requires sudo"
        dtruss -t open "$TARGET" 2> "$TRACE_LOG" &
        sleep "$TIMEOUT"
        pkill -P $$ dtruss || true
    else
        sudo dtruss -t open "$TARGET" 2> "$TRACE_LOG" &
        sleep "$TIMEOUT"
        sudo pkill -P $$ dtruss || true
    fi
    
    # Extract .dylib files from trace
    grep -E '\.dylib' "$TRACE_LOG" 2>/dev/null | \
        grep -v "err = " | \
        sed -E 's/.*"([^"]+\.dylib[^"]*)".*/\1/' | \
        sort -u | \
    while read lib; do
        [[ -n "$lib" ]] && echo "{\"name\":\"$(basename "$lib")\",\"path\":\"$lib\",\"source\":\"runtime\"}"
    done | jq -s '.' > "$OUTPUT_DIR/runtime-libs.json"
    
    # Merge static and runtime libraries
    jq -s '.[0] + .[1] | unique_by(.path)' "$DYNAMIC_LIBS" "$OUTPUT_DIR/runtime-libs.json" > "$OUTPUT_DIR/all-libs.json"
    mv "$OUTPUT_DIR/all-libs.json" "$DYNAMIC_LIBS"
    
    echo "✓ Captured $(jq '[.[] | select(.source == "runtime")] | length' "$DYNAMIC_LIBS") runtime libraries"
fi

echo ""
echo "=== Step 4: Merge into final SBOM ==="
jq --slurpfile libs "$DYNAMIC_LIBS" '. + {
    dynamicDependencies: {
        libraries: $libs[0],
        captureMethod: "otool+dtruss",
        timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
        summary: {
            total: ($libs[0] | length),
            static: ($libs[0] | map(select(.source == "otool")) | length),
            runtime: ($libs[0] | map(select(.source == "runtime")) | length)
        }
    }
}' "$STATIC_SBOM" > "$FINAL_SBOM"

echo "✓ Created: $FINAL_SBOM"
echo ""
echo "=== Summary ==="
echo "Packages (Syft): $(jq '.artifacts | length' "$STATIC_SBOM")"
echo "Dynamic libraries: $(jq '.dynamicDependencies.summary.total' "$FINAL_SBOM")"
echo "  - Static (otool): $(jq '.dynamicDependencies.summary.static' "$FINAL_SBOM")"
echo "  - Runtime (dtruss): $(jq '.dynamicDependencies.summary.runtime' "$FINAL_SBOM")"
echo ""
echo "Done! Results in: $OUTPUT_DIR"
