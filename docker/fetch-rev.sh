#!/bin/sh
# Check out one commit of a git repository without its history.
# Usage: fetch-rev.sh <url> <commit> <directory>
set -eu
url=$1 rev=$2 dir=$3
git init -q "$dir"
git -C "$dir" remote add origin "$url"
git -C "$dir" fetch -q --depth 1 origin "$rev"
git -C "$dir" checkout -q FETCH_HEAD
