#!/usr/bin/bash

MAP_FILE=map-ciao.osm
CONFIG_FILE=green-mapconfig.xml

PGSQL_SERVER_ADDR=172.18.0.2
PGSQL_DB_NAME=osm-pesi

export PGPASSWORD=admin
dropdb --force -U admin -h $PGSQL_SERVER_ADDR --echo $PGSQL_DB_NAME
createdb -U admin -h $PGSQL_SERVER_ADDR --echo $PGSQL_DB_NAME

RETURN=$?

if [ $RETURN -ne 0 ];
then
  echo "ERROR: psql: failed to clear DB"
  exit $RETURN
fi 

../build/./osm2pgrouting \
    -f $MAP_FILE \
    -c $CONFIG_FILE \
    --dbname $PGSQL_DB_NAME \
    -U admin \
    -W admin \
    -h $PGSQL_SERVER_ADDR \
    --tags 