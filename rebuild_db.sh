#!/usr/bin/bash

# rebuild_db.sh
# Recreates the database from scratch
# Copyright (c) 2024 Jacopo Maltagliati (j.maltagliati@campus.unimib.it)
# This file is part of the MUSA micromobility project

CONFIG_FILE=mapconfig.xml

GREEN_AREA_TAG_ID_BELOW=3000

POLLUTION_OVERLAY_LOW=pollution_low.png
POLLUTION_OVERLAY_MEDIUM=pollution_medium.png
POLLUTION_OVERLAY_HIGH=pollution_high.png
MIN_AQI=1
MAX_AQI=500

TRAFFIC_OVERLAY_LOW=bicocca-traffic-low.png
TRAFFIC_OVERLAY_MEDIUM=bicocca-traffic.png
TRAFFIC_OVERLAY_HIGH=bicocca-accident.png
MIN_TRAFFIC=1
MAX_TRAFFIC=5

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
	((COUNT = COUNT + 1))
done

echo Imported $COUNT functions.

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Relabeling Crossings..."
echo "-----------------------------------------------------------------------------"

query "CALL relabel_crossings()"

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Creating Green Areas and Ways..."
echo "-----------------------------------------------------------------------------"

query "CALL make_green_areas($GREEN_AREA_TAG_ID_BELOW)"
query " \
  ALTER TABLE ways ADD COLUMN IF NOT EXISTS green boolean DEFAULT false; \
  UPDATE ways w SET green = true FROM green_areas ga WHERE (ST_Contains(ga.geom, w.the_geom) OR ST_Crosses(ga.geom, w.the_geom)) AND w.highway IS NOT NULL"

# -----------------------------------------------------------------------------

echo "-----------------------------------------------------------------------------"
echo " Removing unconnected components from the global graph..."
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
echo " Creating additional tables"
echo "-----------------------------------------------------------------------------"

query "CREATE TABLE pois (id BIGINT PRIMARY KEY, \
	type TEXT NOT NULL, \
	lon DOUBLE PRECISION NOT NULL, \
	lat DOUBLE PRECISION NOT NULL, \
	name TEXT NOT NULL, description TEXT, \
	bikes INTEGER, scooters INTEGER, ebikes INTEGER)"
query "\copy pois FROM data/pois.csv WITH CSV DELIMITER ','"

query "CREATE TYPE vehicle_kind AS ENUM ('none', 'bike', 'ebike', 'scooter')"
query "CREATE TABLE vehicles (kind vehicle_kind PRIMARY KEY, \
	speed DOUBLE PRECISION NOT NULL, \
	cost DOUBLE PRECISION NOT NULL, \
	green INTEGER NOT NULL)"
query "\copy vehicles FROM data/vehicles.csv WITH CSV DELIMITER ','"

mkdir -p .cache

query "\copy (SELECT id, x1, y1, x2, y2 FROM ways) TO .cache/ways.csv WITH CSV DELIMITER ','"

echo "Processing air pollution overlays..."
add_overlay $POLLUTION_OVERLAY_LOW $MIN_AQI $MAX_AQI .cache/ways.csv .cache/work1.csv
add_overlay $POLLUTION_OVERLAY_MEDIUM $MIN_AQI $MAX_AQI .cache/work1.csv .cache/work2.csv
add_overlay $POLLUTION_OVERLAY_HIGH $MIN_AQI $MAX_AQI .cache/work2.csv .cache/pollution.csv

echo "Processing traffic overlays..."
add_overlay $TRAFFIC_OVERLAY_LOW $MIN_TRAFFIC $MAX_TRAFFIC .cache/pollution.csv .cache/work1.csv
add_overlay $TRAFFIC_OVERLAY_MEDIUM $MIN_TRAFFIC $MAX_TRAFFIC .cache/work1.csv .cache/work2.csv
add_overlay $TRAFFIC_OVERLAY_HIGH $MIN_TRAFFIC $MAX_TRAFFIC .cache/work2.csv .cache/overlays.csv

echo "Creating data table"
query "CREATE TABLE data (id BIGINT PRIMARY KEY, \
						  pm2_low INTEGER, \
						  pm2_medium INTEGER, pm2_high INTEGER, \
						  traffic_low INTEGER, \
						  traffic_medium INTEGER, traffic_high INTEGER, \
						  comf_n DOUBLE PRECISION, qualinf_n DOUBLE PRECISION, \
						  sic_n DOUBLE PRECISION, acc_n DOUBLE PRECISION, \
						  walk_n DOUBLE PRECISION)"
query "\copy data(id, pm2_low, pm2_medium, pm2_high, \
       traffic_low, traffic_medium, traffic_high) \
	   FROM PROGRAM 'cut -d , -f1,6,7,8,9,10,11 .cache/overlays.csv' WITH CSV DELIMITER ',' NULL 'NULL'"
	  
query "CREATE TABLE wi (id BIGINT PRIMARY KEY, \
						  comf_n DOUBLE PRECISION, qualinf_n DOUBLE PRECISION, \
						  sic_n DOUBLE PRECISION, acc_n DOUBLE PRECISION, \
						  walk_n DOUBLE PRECISION)"
	  
query "\copy wi(id, comf_n, qualinf_n, sic_n, acc_n, walk_n) \
	   FROM data/wi_210225.csv WITH CSV HEADER DELIMITER ',' NULL 'NULL'"
	   
query "UPDATE data
SET 
    comf_n = COALESCE(data.comf_n, wi.comf_n),
    qualinf_n = COALESCE(data.qualinf_n, wi.qualinf_n),
    sic_n = COALESCE(data.sic_n, wi.sic_n),
    acc_n = COALESCE(data.acc_n, wi.acc_n),
    walk_n = COALESCE(data.walk_n, wi.walk_n)
FROM wi
WHERE data.id = wi.id;
"
query "DROP TABLE wi"

rm -r .cache

echo "-----------------------------------------------------------------------------"
echo " All done!"
echo "-----------------------------------------------------------------------------"
