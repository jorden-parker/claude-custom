#!/usr/bin/env bash
set -eu
input_file="$1"
wc -l < "$input_file" | tr -d ' '
