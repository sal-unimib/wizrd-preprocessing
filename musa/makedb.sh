#!/usr/bin/bash

MAP_FILE=bicocca-2024-07-09.osm
CONFIG_FILE=mapconfig.xml

PGSQL_SERVER_ADDR=172.19.0.3
PGSQL_DB_NAME=mapserver

PGSQL_USER=admin
PGSQL_PASS=admin

POLLUTION_PNG=blob.png
TRAFFIC_PNG=bicocca-traffic.png

panic() {
  RET=$1

  if [ $RET -ne 0 ]; then
    echo FATAL: $2
    exit $RET
  fi
}

hash psql 2>/dev/null 
panic $? "PostgreSQL is required to run this script"

export PGPASSWORD=$PGSQL_PASS

echo "*** Phase 1 - Recreating DB from scratch... ***"
dropdb --force -U $PGSQL_USER -h $PGSQL_SERVER_ADDR --echo $PGSQL_DB_NAME
createdb -U $PGSQL_USER -h $PGSQL_SERVER_ADDR --echo $PGSQL_DB_NAME
panic $? "psql: failed to recreate DB"

echo "*** Phase 2 - Importing data from OSM dump file... ***"
../build/./osm2pgrouting \
    -f $MAP_FILE \
    -c $CONFIG_FILE \
    --dbname $PGSQL_DB_NAME \
    -U $PGSQL_USER \
    -W $PGSQL_PASS \
    -h $PGSQL_SERVER_ADDR \
    --tags \
    --attributes
panic $? "osm2pgrouting: failed to populate DB"

echo "Renaming columns..."
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c 'ALTER TABLE ways RENAME COLUMN gid TO id;'
panic $? "psql: failed to rename column: ways.gid -> ways.id"

echo "*** Phase 3 - Adding required extensions... ***"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c 'CREATE EXTENSION pgRouting CASCADE'
panic $? "psql: failed to create extension: pgRouting"

echo "*** Phase 4 - Importing functions... ***"
COUNT=0

for FUNC in functions/*.sql; do
  echo Processing $FUNC...
  psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -f $FUNC
  panic $? "psql: failed to add function to DB"
  ((COUNT=COUNT+1))
done

echo Imported $COUNT functions.

echo "*** Phase 5 - Importing pollution data... ***"

mkdir -p .cache
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "\copy (SELECT id, x1, y1, x2, y2 FROM ways) TO .cache/ways.csv WITH CSV DELIMITER ','"
panic $? "psql: failed to copy data from DB: ways (id,x1,y1,x2,y2)"
pollution/./tool pollution/$POLLUTION_PNG $(cat pollution/bbox.txt) < .cache/ways.csv > .cache/pollution.csv
panic $? "pollution/tool: failed"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "CREATE TABLE pollution (id BIGINT PRIMARY KEY, pm2 INTEGER)"
panic $? "psql: failed to create table: pollution"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "\copy pollution FROM .cache/pollution.csv WITH CSV DELIMITER ','"
panic $? "psql: failed to copy data to DB: pollution (id,pm2)"
rm -r .cache
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "SELECT w.*, p.pm2 INTO temp FROM ways w JOIN pollution p ON p.id = w.id"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "DROP TABLE ways"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "ALTER TABLE temp RENAME TO ways"

echo "*** Phase 6 - Importing traffic data... ***"

mkdir -p .cache
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "\copy (SELECT id, x1, y1, x2, y2 FROM ways) TO .cache/ways.csv WITH CSV DELIMITER ','"
panic $? "psql: failed to copy data from DB: ways (id,x1,y1,x2,y2)"
traffic/./tool traffic/$TRAFFIC_PNG $(cat traffic/bbox.txt) < .cache/ways.csv > .cache/traffic.csv
panic $? "traffic/tool: failed"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "CREATE TABLE traffic (id BIGINT PRIMARY KEY, traffic INTEGER)"
panic $? "psql: failed to create table: traffic"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "\copy traffic FROM .cache/traffic.csv WITH CSV DELIMITER ','"
panic $? "psql: failed to copy data to DB: traffic (id,pm2)"
rm -r .cache
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "SELECT w.*, p.traffic INTO temp FROM ways w JOIN traffic p ON p.id = w.id"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "DROP TABLE ways"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "ALTER TABLE temp RENAME TO ways"

echo "All done!"
