#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
tool="$repo/bin/extract-mtp-weights"
sandbox="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
trap 'rm -rf "$sandbox"' EXIT
failures=0

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

write_fixture() {
  python3 -I - "$1" "${2:-}" <<'PY'
import json
import os
import struct
import sys

model_dir, variant = sys.argv[1], sys.argv[2]


def write_shard(name, tensors):
    header = {}
    body = b""
    for tensor_name, dtype, shape, data in tensors:
        header[tensor_name] = {
            "dtype": dtype,
            "shape": shape,
            "data_offsets": [len(body), len(body) + len(data)],
        }
        body += data
    encoded = json.dumps(header).encode("utf-8")
    with open(os.path.join(model_dir, name), "wb") as handle:
        handle.write(struct.pack("<Q", len(encoded)))
        handle.write(encoded)
        handle.write(body)


os.makedirs(model_dir, exist_ok=True)
first_shard = [("language_model.model.embed_tokens.weight", "F16", [2, 2], bytes(range(8, 16)))]
if variant != "plain":
    first_shard.insert(0, ("language_model.mtp.fc.weight", "F16", [2, 2], bytes(range(8))))
write_shard("model-00001-of-00002.safetensors", first_shard)
if variant != "plain":
    write_shard(
        "model-00002-of-00002.safetensors",
        [("mtp.layers.0.mlp.gate_proj.scales", "F32", [1], bytes([9, 8, 7, 6]))],
    )
PY
}

verify_output() {
  python3 -I - "$1" <<'PY'
import json
import struct
import sys

path = sys.argv[1]
expected = {
    "language_model.mtp.fc.weight": ("F16", [2, 2], bytes(range(8))),
    "mtp.layers.0.mlp.gate_proj.scales": ("F32", [1], bytes([9, 8, 7, 6])),
}
with open(path, "rb") as handle:
    (length,) = struct.unpack("<Q", handle.read(8))
    header = json.loads(handle.read(length))
    body = handle.read()
if length % 8 != 0:
    sys.exit("header length is not a multiple of 8")
header.pop("__metadata__", None)
if set(header) != set(expected):
    sys.exit(f"tensors are {sorted(header)}")
for name, (dtype, shape, data) in expected.items():
    info = header[name]
    start, end = info["data_offsets"]
    if info["dtype"] != dtype or info["shape"] != shape or body[start:end] != data:
        sys.exit(f"mismatch for {name}")
PY
}

mtime_ns() {
  python3 -I -c 'import os, sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$1"
}

model="$sandbox/model"
write_fixture "$model"
output="$model/mtp/weights.safetensors"

"$tool" "$model" >"$sandbox/out" 2>"$sandbox/err"
check "extract exits 0" test "$?" -eq 0
check "extract prints the output path" grep -qxF "$output" "$sandbox/out"
check "output holds exactly the mtp tensors with identical bytes, dtypes and shapes" verify_output "$output"

before="$(mtime_ns "$output")"
sleep 1
"$tool" "$model" >/dev/null 2>&1
check "a second run exits 0" test "$?" -eq 0
check "a second run leaves the file unchanged" test "$(mtime_ns "$output")" = "$before"

plain="$sandbox/plain"
write_fixture "$plain" plain
"$tool" "$plain" >"$sandbox/out" 2>"$sandbox/err"
check "a model without mtp tensors exits 1" test "$?" -eq 1
check "a model without mtp tensors says so" grep -qF "extract-mtp-weights: no mtp.* tensors in $plain" "$sandbox/err"
check "a model without mtp tensors gets no output file" test ! -e "$plain/mtp/weights.safetensors"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
