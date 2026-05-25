#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  sync-debug-plugins.sh --source-dir Plugins --products-dir build/DerivedData/Build/Products/Debug --output-dir build/LocalPlugins

Synchronizes Debug plugin bundles already built by the main MacTools scheme into
development .mactoolsplugin packages, generates a local debug catalog, and copies
the packages into the MacTools Dev installed plugin store.

This script does not run xcodebuild. Run it after the Debug app build.
USAGE
}

SOURCE_DIR=""
PRODUCTS_DIR=""
OUTPUT_DIR=""
INSTALL_DIR="$HOME/Library/Application Support/MacTools Dev/Plugins/Installed"
SKIP_INSTALL=0
PLUGIN_FILTERS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-dir)
            SOURCE_DIR="${2:-}"
            shift 2
            ;;
        --products-dir)
            PRODUCTS_DIR="${2:-}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="${2:-}"
            shift 2
            ;;
        --plugin)
            IFS=',' read -r -a raw_plugin_filters <<< "${2:-}"
            for raw_plugin_filter in "${raw_plugin_filters[@]}"; do
                raw_plugin_filter="${raw_plugin_filter#"${raw_plugin_filter%%[![:space:]]*}"}"
                raw_plugin_filter="${raw_plugin_filter%"${raw_plugin_filter##*[![:space:]]}"}"
                [[ -n "$raw_plugin_filter" ]] && PLUGIN_FILTERS+=("$raw_plugin_filter")
            done
            shift 2
            ;;
        --skip-install)
            SKIP_INSTALL=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$SOURCE_DIR" || -z "$PRODUCTS_DIR" || -z "$OUTPUT_DIR" ]]; then
    usage >&2
    exit 1
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" 2>/dev/null && pwd || true)"
if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
    echo "Plugin source directory not found: $SOURCE_DIR" >&2
    exit 1
fi

PRODUCTS_DIR="$(cd "$PRODUCTS_DIR" 2>/dev/null && pwd || true)"
if [[ -z "$PRODUCTS_DIR" || ! -d "$PRODUCTS_DIR" ]]; then
    echo "Debug build products directory not found. Run 'make build' first: $PRODUCTS_DIR" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_DIR="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)"
PACKAGES_DIR="$OUTPUT_DIR/Packages"
CATALOG_PATH="$OUTPUT_DIR/catalog.dev.json"

mkdir -p "$PACKAGES_DIR"
if [[ "$SKIP_INSTALL" != "1" ]]; then
    mkdir -p "$INSTALL_DIR"
fi

json_value() {
    local file="$1"
    local expression="$2"
    python3 - "$file" "$expression" <<'PY'
import json
import sys

path, expression = sys.argv[1:]
data = json.load(open(path))
value = data
for part in expression.split("."):
    if not part:
        continue
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break
if value is None:
    print("")
else:
    print(value)
PY
}

discover_candidates() {
    if [[ -f "$SOURCE_DIR/plugin.json" ]]; then
        printf '%s\n' "$SOURCE_DIR"
        return
    fi

    find "$SOURCE_DIR" -maxdepth 3 -name plugin.json -print \
        | while IFS= read -r path; do
            dirname "$path"
        done \
        | sort -u
}

matches_filter() {
    local candidate="$1"

    if [[ ${#PLUGIN_FILTERS[@]} -eq 0 ]]; then
        return 0
    fi

    local basename
    basename="$(basename "$candidate")"

    local id
    id="$(json_value "$candidate/plugin.json" "id")"

    local filter
    for filter in "${PLUGIN_FILTERS[@]}"; do
        [[ "$basename" == "$filter" ]] && return 0
        [[ -n "$id" && "$id" == "$filter" ]] && return 0
    done

    return 1
}

copy_package_to_installed_store() {
    local package_path="$1"
    local plugin_id="$2"
    local destination="$INSTALL_DIR/$plugin_id.mactoolsplugin"
    local staging="$INSTALL_DIR/.$plugin_id.syncing.$$.mactoolsplugin"

    rm -rf "$staging"
    ditto "$package_path" "$staging"
    rm -rf "$destination"
    mv "$staging" "$destination"
}

packages=()
while IFS= read -r plugin_root; do
    [[ -n "$plugin_root" ]] || continue
    matches_filter "$plugin_root" || continue

    manifest="$plugin_root/plugin.json"
    plugin_id="$(json_value "$manifest" "id")"
    bundle_relative_path="$(json_value "$manifest" "bundleRelativePath")"
    bundle_name="$(basename "$bundle_relative_path")"

    if [[ -z "$plugin_id" || -z "$bundle_relative_path" ]]; then
        echo "plugin.json must include id and bundleRelativePath: $manifest" >&2
        exit 1
    fi

    bundle_path="$PRODUCTS_DIR/$bundle_name"
    if [[ ! -d "$bundle_path" ]]; then
        echo "Built plugin bundle not found for $plugin_id: $bundle_path" >&2
        echo "Run 'make build' and ensure the plugin target is included in the MacTools scheme." >&2
        exit 1
    fi

    package_path="$PACKAGES_DIR/$plugin_id.mactoolsplugin"
    rm -rf "$package_path"
    mkdir -p "$package_path/$(dirname "$bundle_relative_path")"
    ditto "$manifest" "$package_path/plugin.json"
    ditto "$bundle_path" "$package_path/$bundle_relative_path"

    if [[ "$SKIP_INSTALL" != "1" ]]; then
        copy_package_to_installed_store "$package_path" "$plugin_id"
    fi

    packages+=("$package_path")
done < <(discover_candidates)

if [[ ${#packages[@]} -eq 0 ]]; then
    if [[ ${#PLUGIN_FILTERS[@]} -gt 0 ]]; then
        echo "No plugin matched requested filters in $SOURCE_DIR: ${PLUGIN_FILTERS[*]}" >&2
    else
        echo "No plugins found in $SOURCE_DIR." >&2
    fi
    exit 1
fi

catalog_args=()
for package in "${packages[@]}"; do
    catalog_args+=(--package "$package")
done

"$REPO_ROOT/scripts/plugins/generate-plugin-catalog.sh" \
    --mode debug \
    --output "$CATALOG_PATH" \
    "${catalog_args[@]}"

echo "Synced ${#packages[@]} debug plugin package(s)."
echo "Catalog: $CATALOG_PATH"
if [[ "$SKIP_INSTALL" != "1" ]]; then
    echo "Installed store: $INSTALL_DIR"
fi
