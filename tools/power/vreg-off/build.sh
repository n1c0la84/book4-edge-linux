#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build vreg_off.ko for the running kernel on Arch (tools/power/build-module.sh,
# against linux-book4-headers). Until 19 November this built in the Fedora
# container against a Fedora-home tree; see docs/fedora-retired.md.
#
#   bash tools/power/vreg-off/build.sh [KERNEL_BUILD_DIR]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
exec bash "$here/../build-module.sh" "$here" "$@"
