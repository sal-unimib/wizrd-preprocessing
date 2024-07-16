#!/usr/bin/bash

CSV_FILE=ways.csv

source ../globals.sh

export PGPASSWORD=$PGSQL_PASS

psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "\copy (SELECT id, x1, y1, x2, y2 FROM ways ORDER BY id ASC) TO $CSV_FILE WITH CSV DELIMITER ','"