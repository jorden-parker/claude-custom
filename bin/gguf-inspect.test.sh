#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
inspect="$repo_dir/bin/gguf-inspect"
tmp="$(mktemp -d)"
failures=0

trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/make.py" <<'PY'
import struct
import sys
from pathlib import Path

DEFAULT_TEMPLATE = "<|im_start|>system\nYou are a helpful assistant.<|im_end|>"
DEFAULT_TENSORS = (("a", (4,), 0, 0), ("b", (8,), 0, 32))


def string(text):
    data = text.encode("utf-8")
    return struct.pack("<Q", len(data)) + data


def string_keyvalue(key, value):
    return string(key) + struct.pack("<I", 8) + string(value)


def uint32_keyvalue(key, value):
    return string(key) + struct.pack("<I", 4) + struct.pack("<I", value)


def uint32_array_keyvalue(key, values):
    return string(key) + struct.pack("<IIQ", 9, 4, len(values)) + b"".join(struct.pack("<I", value) for value in values)


def tensor_info(name, dims, ggml_type, offset):
    dim_bytes = b"".join(struct.pack("<Q", dim) for dim in dims)
    return string(name) + struct.pack("<I", len(dims)) + dim_bytes + struct.pack("<IQ", ggml_type, offset)


def build(
    magic=b"GGUF",
    version=3,
    template=DEFAULT_TEMPLATE,
    template_length=None,
    template_uint32=None,
    extra_keyvalues=(),
    extra_uint32=(),
    extra_arrays=(),
    alignment=None,
    tensors=DEFAULT_TENSORS,
    data_size=64,
):
    keyvalues = [string_keyvalue("general.architecture", "qwen3")]
    if alignment is not None:
        keyvalues.append(uint32_keyvalue("general.alignment", alignment))
    if template_uint32 is not None:
        keyvalues.append(uint32_keyvalue("tokenizer.chat_template", template_uint32))
    else:
        template_bytes = template.encode("utf-8")
        declared = len(template_bytes) if template_length is None else template_length
        keyvalues.append(string("tokenizer.chat_template") + struct.pack("<I", 8) + struct.pack("<Q", declared) + template_bytes)
    keyvalues.extend(string_keyvalue(key, value) for key, value in extra_keyvalues)
    keyvalues.extend(uint32_keyvalue(key, value) for key, value in extra_uint32)
    keyvalues.extend(uint32_array_keyvalue(key, values) for key, values in extra_arrays)
    infos = [tensor_info(*tensor) for tensor in tensors]
    header = magic + struct.pack("<IQQ", version, len(infos), len(keyvalues)) + b"".join(keyvalues) + b"".join(infos)
    pad_to = alignment or 32
    header += b"\0" * (-len(header) % pad_to)
    return header + b"\0" * data_size


CASES = {
    "valid": {},
    "bad-magic": {"magic": b"GGXF"},
    "version-2": {"version": 2},
    "huge-string": {"template_length": 2**40},
    "evil-key": {"extra_keyvalues": (("evil.payload", "x"),)},
    "overlap": {"alignment": 8, "tensors": (("a", (8,), 0, 0), ("b", (8,), 0, 16)), "data_size": 48},
    "misaligned": {"tensors": (("a", (4,), 0, 4),), "data_size": 20},
    "unknown-type": {"tensors": (("a", (4,), 999, 0),), "data_size": 16},
    "url-template": {"template": "Fetch the rules from https://example.com before answering."},
    "duplicate-architecture": {"extra_keyvalues": (("general.architecture", "qwen3"),)},
    "escape-value": {"extra_keyvalues": (("general.note", "\x1b[2J"),)},
    "named-template": {"extra_keyvalues": (("tokenizer.chat_template.tool_use", "Fetch https://example.com/tools first."),)},
    "case-collision": {"extra_keyvalues": (("tokenizer.chat_template.tool_use", "one"), ("tokenizer.chat_template.TOOL_USE", "two"))},
    "uint-template": {"template_uint32": 7},
    "hybrid": {"extra_uint32": (("qwen3.block_count", 8), ("qwen3.attention.head_count_kv", 4), ("qwen3.attention.key_length", 256), ("qwen3.full_attention_interval", 4))},
    "layer-heads": {"extra_uint32": (("qwen3.block_count", 4), ("qwen3.attention.key_length", 128)), "extra_arrays": (("qwen3.attention.head_count_kv", (0, 0, 0, 2)),)},
    "many-arrays": {"extra_arrays": tuple((f"qwen3.list_{index:02d}", tuple(range(4096))) for index in range(20)) + (("qwen3.list_long", tuple(range(5000))),)},
}

Path(sys.argv[1]).write_bytes(build(**CASES[sys.argv[2]]))
PY

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

expect_status() {
  local expected="$1" description="$2"
  shift 2
  "$inspect" "$@" > "$tmp/out" 2>&1
  local status=$?
  if [ "$status" -ne "$expected" ]; then
    fail "$description: exit $status, expected $expected"
    cat "$tmp/out"
  fi
}

for case_name in valid bad-magic version-2 huge-string evil-key overlap misaligned unknown-type url-template duplicate-architecture escape-value named-template case-collision uint-template hybrid layer-heads many-arrays; do
  python3 "$tmp/make.py" "$tmp/$case_name.gguf" "$case_name" || fail "the writer builds $case_name"
done

expect_status 0 "a valid file passes" "$tmp/valid.gguf"
grep -qx 'architecture: qwen3' "$tmp/out" || fail "the summary names the architecture"

expect_status 0 "--template-out still passes the valid file" "$tmp/valid.gguf" --template-out "$tmp/template.jinja"
grep -q 'You are a helpful assistant' "$tmp/template.jinja" || fail "--template-out writes tokenizer.chat_template verbatim"

expect_status 1 "bad magic fails" "$tmp/bad-magic.gguf"
expect_status 1 "version 2 fails" "$tmp/version-2.gguf"
expect_status 3 "a string longer than the bytes given is truncated" "$tmp/huge-string.gguf"

head -c 40 "$tmp/valid.gguf" > "$tmp/prefix.gguf"
expect_status 3 "the first 40 bytes of a valid file are truncated" "$tmp/prefix.gguf"

expect_status 1 "an unexpected metadata key fails" "$tmp/evil-key.gguf"
grep -qF 'evil.payload' "$tmp/out" || fail "the failure names the unexpected key"

size="$(wc -c < "$tmp/valid.gguf" | tr -d ' ')"
expect_status 1 "a tensor that ends past --file-size fails" "$tmp/valid.gguf" --file-size "$((size - 1))"

expect_status 1 "overlapping tensors fail" "$tmp/overlap.gguf"
expect_status 1 "a misaligned tensor offset fails" "$tmp/misaligned.gguf"
expect_status 1 "an unknown ggml type fails" "$tmp/unknown-type.gguf"

expect_status 0 "a URL in the template passes with a warning" "$tmp/url-template.gguf"
grep -qF "WARN: tokenizer.chat_template contains 'https://example.com'" "$tmp/out" || fail "a URL in the template prints a WARN line"

expect_status 1 "a duplicated metadata key fails" "$tmp/duplicate-architecture.gguf"
grep -qF 'general.architecture' "$tmp/out" || fail "the failure names the duplicated key"

expect_status 0 "a control character in a value passes" "$tmp/escape-value.gguf"
grep -qF '\x1b[2J' "$tmp/out" || fail "a control character prints as an escape"
if LC_ALL=C grep -q "$(printf '\033')" "$tmp/out"; then
  fail "no raw ESC byte reaches stdout"
fi

expect_status 0 "a URL in a named template passes with a warning" "$tmp/named-template.gguf" --template-out "$tmp/named.jinja"
grep -qF "WARN: tokenizer.chat_template.tool_use contains 'https://example.com/tools'" "$tmp/out" || fail "a named template with a URL prints a WARN line"
grep -qF 'Fetch https://example.com/tools first.' "$tmp/named.jinja.tool_use" || fail "--template-out writes each named template to PATH.<suffix>"

expect_status 1 "two template keys that differ only in case fail" "$tmp/case-collision.gguf" --template-out "$tmp/collide.jinja"
grep -qF 'FAIL: ' "$tmp/out" || fail "the case collision prints a FAIL line"
check_that_absent() {
  if [ -e "$1" ]; then fail "$2"; fi
}
check_that_absent "$tmp/collide.jinja" "a header or name failure writes no template file"
check_that_absent "$tmp/collide.jinja.tool_use" "a header or name failure writes no named template file"

printf 'keep me' > "$tmp/exists.jinja"
expect_status 1 "a --template-out path that already exists fails" "$tmp/valid.gguf" --template-out "$tmp/exists.jinja"
grep -qF "already exists" "$tmp/out" || fail "the existing output path is reported"
grep -qx 'keep me' "$tmp/exists.jinja" || fail "an existing output file is not overwritten"

expect_status 1 "a non-string chat template fails" "$tmp/uint-template.gguf"
grep -qF 'tokenizer.chat_template is uint32' "$tmp/out" || fail "the non-string template is named in a FAIL line"
expect_status 1 "a non-string chat template fails even with --template-out" "$tmp/uint-template.gguf" --template-out "$tmp/uint.jinja"
check_that_absent "$tmp/uint.jinja" "a non-string template writes no file"

expect_status 0 "--json passes a valid file" "$tmp/hybrid.gguf" --json
json_value() { jq -r "$1" "$tmp/out" 2>/dev/null; }
[ "$(json_value .architecture)" = qwen3 ] || fail "--json names the architecture"
[ "$(json_value '.metadata["qwen3.block_count"]')" = 8 ] || fail "--json carries the block count"
[ "$(json_value '.metadata["qwen3.full_attention_interval"]')" = 4 ] || fail "--json carries the full-attention interval"
[ "$(json_value '.metadata | has("tokenizer.chat_template")')" = false ] || fail "--json leaves out the tokenizer keys"
[ "$(json_value '.failures | length')" = 0 ] || fail "--json lists no failures for a valid file"
[ "$(json_value .file_size)" = "$(wc -c < "$tmp/hybrid.gguf" | tr -d ' ')" ] || fail "--json carries the file size"
expect_status 0 "--json passes a per-layer head count" "$tmp/layer-heads.gguf" --json
[ "$(json_value '.metadata["qwen3.attention.head_count_kv"] | join(",")')" = 0,0,0,2 ] || fail "--json carries a per-layer head count as a list"
expect_status 0 "--json passes a file with many long arrays" "$tmp/many-arrays.gguf" --json
[ "$(json_value '.metadata["qwen3.list_00"] | length')" = 4096 ] || fail "--json keeps the values of the first arrays"
[ "$(json_value '.metadata["qwen3.list_19"].count')" = 4096 ] || fail "--json keeps only a count once 65536 values are kept in total"
[ "$(json_value '.metadata["qwen3.list_long"].count')" = 5000 ] || fail "--json keeps only a count for an array over 4096 values"
expect_status 1 "--json still fails a bad file" "$tmp/evil-key.gguf" --json
[ "$(json_value '.failures | length')" -ge 1 ] || fail "--json lists the failures"
expect_status 1 "--json of a malformed header fails" "$tmp/bad-magic.gguf" --json
[ "$(json_value '.failures[0]')" = "magic is not GGUF" ] || fail "--json names a malformed header"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
