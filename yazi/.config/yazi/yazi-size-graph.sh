#!/usr/bin/env bash

dir="${1:-.}"

# Use du to get size in bytes and in human-readable form
mapfile -t lines < <(du -sb "$dir"/* 2>/dev/null | sort -nr)

# Calculate total size in bytes
total=0
for line in "${lines[@]}"; do
  size=${line%%[[:space:]]*}
  total=$((total + size))
done

# Print header
printf "%-30s %-12s %s\n" "Name" "Size" "Usage"

# Print graph for each file
for line in "${lines[@]}"; do
  size=${line%%[[:space:]]*}
  path=${line#*[[:space:]]}
  name=$(basename "$path")

  percent=$((100 * size / total))
  hsize=$(numfmt --to=iec-i --suffix=B "$size")

  bar_len=$((percent / 10))
  bar=$(printf '%*s' "$bar_len" '' | tr ' ' '█')
  space=$(printf '%*s' "$((10 - bar_len))" '')

  printf "%-30s %-12s [%s%s] %3d%%\n" "$name" "$hsize" "$bar" "$space" "$percent"
done
