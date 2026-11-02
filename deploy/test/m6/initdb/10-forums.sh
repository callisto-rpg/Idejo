#!/bin/sh
# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# M6 exit check: one PostgreSQL server, a database and a role of its own for each forum.
set -eu
psql -v ON_ERROR_STOP=1 --username postgres <<SQL
CREATE ROLE forum_a LOGIN PASSWORD '${FORUM_A_PASSWORD}';
CREATE DATABASE forum_a OWNER forum_a;
REVOKE ALL ON DATABASE forum_a FROM PUBLIC;
CREATE ROLE forum_b LOGIN PASSWORD '${FORUM_B_PASSWORD}';
CREATE DATABASE forum_b OWNER forum_b;
REVOKE ALL ON DATABASE forum_b FROM PUBLIC;
SQL
