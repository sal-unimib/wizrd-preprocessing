#!/usr/bin/bash

# rebuild_db.sh
# Recreates the database from scratch
# Copyright (c) 2024 Jacopo Maltagliati (j.maltagliati@campus.unimib.it)
# This file is part of the MUSA micromobility project

CONFIG_FILE=mapconfig.xml

GREEN_AREA_TAG_ID_BELOW=3000

POLLUTION_OVERLAY=blob.png
MIN_AQI=1
MAX_AQI=500

TRAFFIC_OVERLAY=bicocca-traffic2.png
MIN_TRAFFIC=1
MAX_TRAFFIC=4

source globals.sh

query() {
    QUERY=$1

    psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "$QUERY"
    panic $? "psql: failed to execute query: \"$QUERY\""
}

hash psql 2>/dev/null
panic $? "PostgreSQL is required to run this script"

osm2pgrouting/build/./osm2pgrouting > /dev/null
panic $? "You must patch and build osm2pgrouting before running this script"

overlay/./overlay > /dev/null
panic $? "You must build the overlay tool before running this script"

export PGPASSWORD=$PGSQL_PASS

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Recreating DB from scratch..."
echo "-----------------------------------------------------------------------------"

dropdb --force -U $PGSQL_USER -h $PGSQL_SERVER_ADDR --echo $PGSQL_DB_NAME
createdb -U $PGSQL_USER -h $PGSQL_SERVER_ADDR --echo $PGSQL_DB_NAME
panic $? "psql: failed to recreate DB"

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Importing data from OSM dump file..."
echo "-----------------------------------------------------------------------------"

osm2pgrouting/build/./osm2pgrouting \
    -f $MAP_FILE \
    -c $CONFIG_FILE \
    --dbname $PGSQL_DB_NAME \
    -U $PGSQL_USER \
    -W $PGSQL_PASS \
    -h $PGSQL_SERVER_ADDR \
    --tags \
    --attributes \
    --addnodes
panic $? "osm2pgrouting: failed to populate DB"

echo "Renaming columns..."

query "ALTER TABLE ways RENAME COLUMN gid TO id"

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Importing functions..."
echo "-----------------------------------------------------------------------------"

query "CREATE EXTENSION pgRouting CASCADE"

COUNT=0

for FUNC in functions/*.sql; do
  echo Processing $FUNC...
  psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -f $FUNC
  panic $? "psql: failed to add function to DB"
  ((COUNT=COUNT+1))
done

echo Imported $COUNT functions.

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Creating Green Areas and Ways..."
echo "-----------------------------------------------------------------------------"

query "CALL make_green_areas($GREEN_AREA_TAG_ID_BELOW)"
panic $? "psql: failed to create Green Areas"
query " \
  ALTER TABLE ways ADD COLUMN IF NOT EXISTS green boolean DEFAULT false; \
  UPDATE ways w SET green = true FROM green_areas ga WHERE (ST_Contains(ga.geom, w.the_geom) OR ST_Crosses(ga.geom, w.the_geom)) AND w.highway IS NOT NULL"

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Importing external data..."
echo "-----------------------------------------------------------------------------"

mkdir -p .cache

query "\copy (SELECT id, x1, y1, x2, y2 FROM ways) TO .cache/ways.csv WITH CSV DELIMITER ','"

echo "Processing air pollution overlay..."
overlay/./overlay overlay/$POLLUTION_OVERLAY $BB_SW_LON $BB_SW_LAT $BB_NE_LON $BB_NE_LAT $MIN_AQI $MAX_AQI < .cache/ways.csv > .cache/pollution.csv
panic $? "overlay: failed to create air pollution data"

echo "Processing traffic overlay..."
overlay/./overlay overlay/$TRAFFIC_OVERLAY $BB_SW_LON $BB_SW_LAT $BB_NE_LON $BB_NE_LAT $MIN_TRAFFIC $MAX_TRAFFIC < .cache/ways.csv > .cache/traffic.csv
panic $? "overlay: failed to create traffic data"

echo "Creating overlays table"
paste -d , .cache/pollution.csv .cache/traffic.csv > .cache/overlays.csv
panic $? "paste: failed to merge overlays"
query "CREATE TABLE overlays (id BIGINT PRIMARY KEY, pm2 INTEGER, id2 BIGINT, traffic INTEGER)"
query "\copy overlays FROM .cache/overlays.csv WITH CSV DELIMITER ','"

rm -r .cache

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Merging external data..."
echo "-----------------------------------------------------------------------------"

query "SELECT w.*, o.pm2, o.traffic INTO temp FROM ways w JOIN overlays o ON o.id = w.id"
query "DROP TABLE ways"
query "ALTER TABLE temp RENAME TO ways"
query "DROP TABLE overlays"

echo "-----------------------------------------------------------------------------"
echo " All done!"
echo "-----------------------------------------------------------------------------"

