#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Spoken "Front Left" / "Front Right" through the normal output (with the
# four-speaker setup: woofers full range, tweeters the highs via the
# crossover). Run as your user.
set -u
echo "Playing 'Front Left' then 'Front Right', twice..."
speaker-test -D pipewire -c 2 -t wav -l 2 2>&1 | grep -E 'Front|error|rror'
