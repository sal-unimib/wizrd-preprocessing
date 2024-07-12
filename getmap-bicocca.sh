#!/usr/bin/bash

MAP_FILE=bicocca.osm

# ~8MB
BB_BOTTOM_LEFT=9.202734,45.506527
BB_TOP_RIGHT=9.223731,45.527366

panic() {
  RET=$1

  if [ $RET -ne 0 ]; then
    echo FATAL: $2
    exit $RET
  fi
}

hash curl 2>/dev/null 
panic $? "\"curl\" is required to run this script"

hash osmconvert 2>/dev/null 
panic $? "\"osmconvert\" is required to run this script"

mkdir -p .cache/

curl -o .cache/temp.osm https://overpass-api.de/api/map?bbox=$BB_BOTTOM_LEFT,$BB_TOP_RIGHT
osmconvert .cache/temp.osm --complete-ways --drop-author --drop-version --out-osm -o=$MAP_FILE

rm -r .cache/