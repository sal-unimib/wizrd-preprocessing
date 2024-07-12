#!/usr/bin/bash

MAP_FILE=bicocca.osm
CONFIG_FILE=mapconfig.xml

PGSQL_SERVER_ADDR=172.18.0.2
PGSQL_DB_NAME=mapserver

PGSQL_USER=admin
PGSQL_PASS=admin

GREEN_AREA_TAG_ID_BELOW=3000

POLLUTION_OVERLAY=blob.png
MIN_AQI=1
MAX_AQI=500

TRAFFIC_OVERLAY=bicocca-traffic.png
MIN_TRAFFIC=1
MAX_TRAFFIC=4

panic() {
  RET=$1

  if [ $RET -ne 0 ]; then
    echo FATAL: $2
    exit $RET
  fi
}

hash psql 2>/dev/null
panic $? "PostgreSQL is required to run this script"

osm2pgrouting/build/./osm2pgrouting > /dev/null
panic $? "You must patch and build osm2pgrouting before running this script"

export PGPASSWORD=$PGSQL_PASS

echo "*** Phase 1 - Recreating DB from scratch... ***"
dropdb --force -U $PGSQL_USER -h $PGSQL_SERVER_ADDR --echo $PGSQL_DB_NAME
createdb -U $PGSQL_USER -h $PGSQL_SERVER_ADDR --echo $PGSQL_DB_NAME
panic $? "psql: failed to recreate DB"

echo "*** Phase 2 - Importing data from OSM dump file... ***"
osm2pgrouting/build/./osm2pgrouting \
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

echo "*** Phase 5 - Creating Green Areas and Ways... ***"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "CALL make_green_areas($GREEN_AREA_TAG_ID_BELOW)"
panic $? "psql: failed to create Green Areas"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c " \
ALTER TABLE ways ADD COLUMN IF NOT EXISTS green boolean DEFAULT false; \
UPDATE ways w SET green = true FROM green_areas ga WHERE ST_Contains(ga.geom, w.the_geom) OR ST_Crosses(ga.geom, w.the_geom); \
"
panic $? "psql: failed to mark Green Ways"

echo "*** Phase 6 - Importing data from overlays... ***"

mkdir -p .cache

psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "\copy (SELECT id, x1, y1, x2, y2 FROM ways) TO .cache/ways.csv WITH CSV DELIMITER ','"
panic $? "psql: failed to copy data from DB: ways (id,x1,y1,x2,y2)"

overlay/./overlay overlay/$POLLUTION_OVERLAY $(cat overlay/bbox.txt) $MIN_AQI $MAX_AQI < .cache/ways.csv > .cache/pollution.csv
panic $? "overlay: failed to create air pollution data"
overlay/./overlay overlay/$TRAFFIC_OVERLAY $(cat overlay/bbox.txt) $MIN_TRAFFIC $MAX_TRAFFIC < .cache/ways.csv > .cache/traffic.csv
panic $? "overlay: failed to create traffic data"
paste -d , .cache/pollution.csv .cache/traffic.csv > .cache/overlays.csv
panic $? "paste: failed to merge overlays"

psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "CREATE TABLE overlays (id BIGINT PRIMARY KEY, pm2 INTEGER, id2 BIGINT, traffic INTEGER)"
panic $? "psql: failed to create table: overlays"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "\copy overlays FROM .cache/overlays.csv WITH CSV DELIMITER ','"
panic $? "psql: failed to copy data to DB: overlays (id,pm2,traffic)"

rm -r .cache

psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "SELECT w.*, o.pm2, o.traffic INTO temp FROM ways w JOIN overlays o ON o.id = w.id"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "DROP TABLE ways"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "ALTER TABLE temp RENAME TO ways"
panic $? "psql: failed to recreate main table: ways"
psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "DROP TABLE overlays"

echo "All done!"
