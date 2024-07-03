#!/usr/bin/bash

# ~30MB
BB_BOTTOM_LEFT=9.180,45.490
BB_TOP_RIGHT=9.220,45.530

panic() {
  RET=$1

  if [ $RET -ne 0 ]; then
    echo FATAL: $2
    exit $RET
  fi
}

hash curl 2>/dev/null 
panic $? "curl is required to run this script"

curl -o bicocca-$(date -I).osm https://overpass-api.de/api/map?bbox=$BB_BOTTOM_LEFT,$BB_TOP_RIGHT

# [jm] the following script extracts a portion of the map geofabrik
#      it does not snip the green areas outside the bounding box correctly, 
#      for some reason
# hash osmconvert 2>/dev/null 
# panic $? "\"osmconvert\" not found"

# mkdir -p .cache
# pushd .cache
# echo "*** Downloading PBF map dump Italy/Nord Ovest from geofabrik.de... ***"
# wget http://download.geofabrik.de/europe/italy/nord-ovest-latest.osm.pbf
# wget http://download.geofabrik.de/europe/italy/nord-ovest-latest.osm.pbf.md5
# echo "*** Validating PBF map dump... ***"
# md5sum -c nord-ovest-latest.osm.pbf.md5
# panic $? "md5sum: dump file bad"
# echo "*** Bounding and converting to OSM... ***"
# osmconvert nord-ovest-latest.osm.pbf \
#     -b=$BB_BOTTOM_LEFT,$BB_TOP_RIGHT \
#     --complete-ways \
#     --drop-author \
#     --drop-version \
#     --out-osm \
#     -o=../milano-$(date -I).osm
# popd
# rm -r .cache
