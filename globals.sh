# globals.sh
# Contains global/shared variables
# Copyright (c) 2024 Jacopo Maltagliati (j.maltagliati@campus.unimib.it)
# This file is part of the MUSA micromobility project

# Name of the file used to store the OSM dump
MAP_FILE=bicocca.osm

# Network parameters for connecting to the DB
# Use "wizrd-db" if you're running this in Docker, or
# "localhost" if you're running locally
PGSQL_SERVER_ADDR=wizrd-db
PGSQL_SERVER_PORT=5432 # [jm] This is currently unused

# Connection parameters for the DB
PGSQL_DB_NAME=wizrd
PGSQL_USER=admin
PGSQL_PASS=admin

# Bounding box limits
BB_SW_LON=9.202734
BB_SW_LAT=45.506527
BB_NE_LON=9.223731
BB_NE_LAT=45.527366

# Function for exiting on error
panic() {
  RET=$1

  if [ $RET -ne 0 ]; then
    echo FATAL: $2
    exit $RET
  fi
}
