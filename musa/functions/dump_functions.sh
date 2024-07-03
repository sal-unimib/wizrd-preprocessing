#!/usr/bin/bash

FUNCTION_NAMES=('calculate_cost_advanced' \
                'calculate_cost_advanced_v2' \
                'calculate_time_cost' \
                'calculate_time_cost_v2' \
                'calculate_heuristic_estimate')

PGSQL_SERVER_ADDR=172.18.0.2
PGSQL_DB_NAME=klaus-db

PGSQL_USER=admin
PGSQL_PASS=admin

export PGPASSWORD=$PGSQL_PASS

for FUNCTION_NAME in "${FUNCTION_NAMES[@]}"; do 
    psql -A -t -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c '
SELECT pg_get_functiondef('\'$FUNCTION_NAME\''::regproc)' -o $FUNCTION_NAME.sql
done