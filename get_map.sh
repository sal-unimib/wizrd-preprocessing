#!/usr/bin/bash

# get_map.sh
# Downloads an OSM file containing geometry data for the specified bounding box
# Copyright (c) 2024 Jacopo Maltagliati (j.maltagliati@campus.unimib.it)
# This file is part of the MUSA micromobility project

source globals.sh

hash curl 2>/dev/null 
panic $? "\"curl\" is required to run this script"

hash osmconvert 2>/dev/null 
panic $? "\"osmconvert\" is required to run this script"

mkdir -p .cache/

curl -o .cache/temp.osm https://overpass-api.de/api/map?bbox=$BB_SW_LON,$BB_SW_LAT,$BB_NE_LON,$BB_NE_LAT
osmconvert .cache/temp.osm --complete-ways --drop-author --drop-version --out-osm -o=$MAP_FILE

rm -r .cache/