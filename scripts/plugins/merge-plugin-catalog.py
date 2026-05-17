#!/usr/bin/env python3
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_CATALOG_ID = "com.ggbond.mactools.plugins"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Merge newly built plugin catalog entries into the current production catalog."
    )
    parser.add_argument("--previous", default="docs/plugins/catalog.json")
    parser.add_argument("--updates", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def load_json(path, required=True):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        if required:
            raise
        return None


def unsigned(catalog):
    if catalog is None:
        return None
    result = dict(catalog)
    result.pop("signature", None)
    return result


def catalog_field(previous, updates, key, default=None):
    if previous is not None and key in previous:
        return previous[key]
    if updates is not None and key in updates:
        return updates[key]
    return default


def now_iso8601():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main():
    args = parse_args()
    previous = unsigned(load_json(args.previous, required=False))
    plan = load_json(args.plan)

    selected_ids = plan.get("selectedPluginIDs", [])
    removed_ids = plan.get("removedPluginIDs", [])
    updates_required = bool(selected_ids)
    updates = unsigned(load_json(args.updates, required=updates_required))

    if previous is None and updates is None:
        raise SystemExit("No previous catalog or update catalog is available.")

    merged_entries = {
        entry["id"]: entry
        for entry in (previous or {}).get("plugins", [])
    }

    for plugin_id in removed_ids:
        merged_entries.pop(plugin_id, None)

    update_entries = {
        entry["id"]: entry
        for entry in (updates or {}).get("plugins", [])
    }
    missing_updates = sorted(plugin_id for plugin_id in selected_ids if plugin_id not in update_entries)
    if missing_updates:
        raise SystemExit(
            "Update catalog is missing selected plugin entries: "
            + ", ".join(missing_updates)
        )

    for plugin_id in selected_ids:
        merged_entries[plugin_id] = update_entries[plugin_id]

    schema_version = catalog_field(previous, updates, "schemaVersion", 1)
    plugin_kit_version = catalog_field(previous, updates, "pluginKitVersion", 1)
    catalog = {
        "schemaVersion": schema_version,
        "catalogID": catalog_field(previous, updates, "catalogID", DEFAULT_CATALOG_ID),
        "generatedAt": now_iso8601(),
        "minimumHostVersion": catalog_field(previous, updates, "minimumHostVersion", "0.15.2"),
        "pluginKitVersion": plugin_kit_version,
        "plugins": sorted(merged_entries.values(), key=lambda entry: entry["id"]),
        "revoked": catalog_field(previous, updates, "revoked", []),
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    print(
        f"Merged catalog: {len(selected_ids)} updated, "
        f"{len(removed_ids)} removed, {len(catalog['plugins'])} total plugin(s)."
    )


if __name__ == "__main__":
    main()
