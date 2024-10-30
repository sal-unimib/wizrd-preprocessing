#!/usr/bin/bash

# rebuild_db.sh
# Recreates the database from scratch
# Copyright (c) 2024 Jacopo Maltagliati (j.maltagliati@campus.unimib.it)
# This file is part of the MUSA micromobility project

CONFIG_FILE=mapconfig.xml

GREEN_AREA_TAG_ID_BELOW=3000

POLLUTION_OVERLAY=blob.png
POLLUTION_OVERLAY_LOW=pollution_low.png
POLLUTION_OVERLAY_MEDIUM=pollution_medium.png
POLLUTION_OVERLAY_HIGH=pollution_high.png
MIN_AQI=1
MAX_AQI=500

TRAFFIC_OVERLAY=bicocca-traffic.png
TRAFFIC_OVERLAY_LOW=bicocca-traffic.png
TRAFFIC_OVERLAY_MEDIUM=bicocca-traffic2.png
TRAFFIC_OVERLAY_HIGH=bicocca-traffic2.png
MIN_TRAFFIC=1
MAX_TRAFFIC=4

source globals.sh

query() {
	QUERY=$1

	psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "$QUERY"
	panic $? "psql: failed to execute query: \"$QUERY\""
}

add_overlay() {
	OVERLAY=$1
	MIN=$2
	MAX=$3
	IN=$4
	OUT=$5

	overlay/./overlay overlay/$OVERLAY $BB_SW_LON $BB_SW_LAT $BB_NE_LON $BB_NE_LAT $MIN $MAX <$IN >$OUT
	panic $? "overlay: failed to create traffic data"
}

hash psql 2>/dev/null
panic $? "PostgreSQL is required to run this script"

osm2pgrouting/build/./osm2pgrouting >/dev/null
panic $? "You must patch and build osm2pgrouting before running this script"

overlay/./overlay >/dev/null
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
	--attributes
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
	((COUNT = COUNT + 1))
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

echo "Processing air pollution overlays..."
add_overlay $POLLUTION_OVERLAY $MIN_AQI $MAX_AQI .cache/ways.csv .cache/work1.csv
add_overlay $POLLUTION_OVERLAY_LOW $MIN_AQI $MAX_AQI .cache/work1.csv .cache/work2.csv
add_overlay $POLLUTION_OVERLAY_MEDIUM $MIN_AQI $MAX_AQI .cache/work2.csv .cache/work1.csv
add_overlay $POLLUTION_OVERLAY_HIGH $MIN_AQI $MAX_AQI .cache/work1.csv .cache/pollution.csv

echo "Processing traffic overlays..."
add_overlay $TRAFFIC_OVERLAY $MIN_TRAFFIC $MAX_TRAFFIC .cache/pollution.csv .cache/work1.csv
add_overlay $TRAFFIC_OVERLAY_LOW $MIN_TRAFFIC $MAX_TRAFFIC .cache/work1.csv .cache/work2.csv
add_overlay $TRAFFIC_OVERLAY_MEDIUM $MIN_TRAFFIC $MAX_TRAFFIC .cache/work2.csv .cache/work1.csv
add_overlay $TRAFFIC_OVERLAY_HIGH $MIN_TRAFFIC $MAX_TRAFFIC .cache/work1.csv .cache/overlays.csv

echo "Creating overlay table"
query "CREATE TABLE overlays (id BIGINT PRIMARY KEY,					\
							  x1 DOUBLE PRECISION, y1 DOUBLE PRECISION,	\
							  x2 DOUBLE PRECISION, y2 DOUBLE PRECISION,	\
							  pm2 INTEGER, pm2_low INTEGER, 			\
							  pm2_medium INTEGER, pm2_high INTEGER,		\
							  traffic INTEGER, traffic_low INTEGER,     \
							  traffic_medium INTEGER, traffic_high INTEGER)"
query "\copy overlays FROM .cache/overlays.csv WITH CSV DELIMITER ','"

rm -r .cache

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Merging overlay data..."
echo "-----------------------------------------------------------------------------"

query "SELECT w.*, o.pm2, o.pm2_low, o.pm2_medium, o.pm2_high, o.traffic, o.traffic_low, o.traffic_medium, o.traffic_high \
 INTO temp FROM ways w JOIN overlays o ON o.id = w.id"
query "DROP TABLE ways"
query "ALTER TABLE temp RENAME TO ways"
query "DROP TABLE overlays"

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Removing unconnected components from the gloabl graph..."
echo "-----------------------------------------------------------------------------"

query "DELETE FROM ways WHERE highway IS NULL"
query "CREATE TABLE connected_comps AS \
	SELECT component, COUNT(node) as cont \
	FROM pgr_connectedComponents( \
		'SELECT * \
		FROM ways') \
	GROUP BY component \
	ORDER BY cont DESC"
query "CREATE TABLE tmp_ways AS \
	SELECT * \
	FROM pgr_connectedComponents( \
		'SELECT * \
		FROM ways') \
	JOIN ways w ON w.source = node \
	WHERE component = (SELECT component \
	FROM connected_comps \
	WHERE cont IN ( \
		SELECT MAX(cont) \
		FROM connected_comps));"
query "ALTER TABLE tmp_ways \
	DROP COLUMN seq, \
	DROP COLUMN component, \
	DROP COLUMN node"
query "DROP TABLE ways"
query "ALTER TABLE tmp_ways RENAME TO ways"
query "CREATE TABLE ways_vertices_pgr_tmp AS \
	SELECT * \
	FROM ways_vertices_pgr \
	WHERE id IN (SELECT source FROM ways) OR id IN (SELECT target FROM ways);"

query "DROP TABLE ways_vertices_pgr;"

query "ALTER TABLE ways_vertices_pgr_tmp RENAME TO ways_vertices_pgr;"

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Changing values in 'one_way' and removing leftovers"
echo "-----------------------------------------------------------------------------"

query "UPDATE ways SET one_way = -1 WHERE one_way = 1"
query "UPDATE ways SET one_way = +1 WHERE one_way = 0 OR one_way = 2"
query "ALTER TABLE ways DROP COLUMN oneway"
query "DROP TABLE green_areas"
query "DROP TABLE connected_comps"
query "DROP TABLE IF EXISTS pointsofinterest"

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Creating POIs table"
echo "-----------------------------------------------------------------------------"

query "CREATE TABLE pois (id BIGINT PRIMARY KEY, \
	type TEXT, \
	lon DOUBLE PRECISION, \
	lat DOUBLE PRECISION, \
	name TEXT, description TEXT, \
	bikes INTEGER, scooters INTEGER, ebikes INTEGER)"
query "\copy pois FROM poi/data.csv WITH CSV DELIMITER ','"

echo "-----------------------------------------------------------------------------"
echo " All done!"
echo "-----------------------------------------------------------------------------"
