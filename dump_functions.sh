#!/usr/bin/bash

# dump_functions.sh
# Dumps all custom function definitions from the DB 
# Copyright (c) 2024 Jacopo Maltagliati (j.maltagliati@campus.unimib.it)
# This file is part of the MUSA micromobility project

FUNCTION_NAMES=('calculate_cost_advanced_new' \
                'calculate_heuristic_estimate' \
                'make_green_areas')

source globals.sh

export PGPASSWORD=$PGSQL_PASS

mkdir -p functions/

for FUNCTION_NAME in "${FUNCTION_NAMES[@]}"; do 
    psql -A -t -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c '
SELECT pg_get_functiondef('\'$FUNCTION_NAME\''::regproc)' -o functions/$FUNCTION_NAME.sql
done
