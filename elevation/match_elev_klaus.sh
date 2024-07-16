PGSQL_SERVER_ADDR=172.18.0.2
PGSQL_DB_NAME=klaus-db
PGSQL_USER=admin
PGSQL_PASS=admin

export PGPASSWORD=$PGSQL_PASS

panic() {
  RET=$1

  if [ $RET -ne 0 ]; then
    echo FATAL: $2
    exit $RET
  fi
}

query() {
    QUERY=$1

    psql -U $PGSQL_USER -h $PGSQL_SERVER_ADDR -d $PGSQL_DB_NAME -c "$QUERY"
    panic $? "psql: failed to execute query: \"$QUERY\""
}

query "DROP TABLE IF EXISTS elev_rej"
query "CREATE TABLE elev_rej (id BIGINT PRIMARY KEY, x1 DOUBLE PRECISION, y1 DOUBLE PRECISION, x2 DOUBLE PRECISION, y2 DOUBLE PRECISION)"
query "\copy elev_rej FROM rejects.csv WITH CSV DELIMITER ','"
query "\copy (SELECT r.id,source_elevation,target_elevation FROM edges_noded e JOIN elev_rej r ON e.x1 = r.x1 AND e.x2 = r.x2 AND e.y1 = r.y1 AND e.y2 = r.y2) TO klaus_elev.csv WITH CSV DELIMITER ','"