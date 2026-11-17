#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# User case (d): the remote user dev does not exist when the image is built; common-utils creates it and the feature installs after it.
. "$(dirname "$0")/scenario.sh"

check "common-utils created dev before the feature ran (installsAfter)" id dev
user_case dev /home/dev

finish
