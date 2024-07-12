CREATE OR REPLACE PROCEDURE public.make_green_areas(IN max_tag_id integer)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
this_id bigint;
this_geom geometry;
cluster_id_match integer;

id_a bigint;
id_b bigint;

BEGIN
DROP TABLE IF EXISTS green_areas;
CREATE TABLE green_areas (cluster_id serial, ids bigint[], geom geometry);
CREATE INDEX ON green_areas USING GIST(geom);

-- Iterate through linestrings, assigning each to a cluster (if there is an intersection)
-- or creating a new cluster (if there is not)
-- [jm] Only include ways with tag_id < 3000 (refer to mapconfig.xml)
FOR this_id, this_geom IN SELECT id, the_geom FROM (SELECT * FROM ways WHERE tag_id < 3000) LOOP
  -- Look for an intersecting cluster.  (There may be more than one.)
  SELECT cluster_id FROM green_areas WHERE ST_Intersects(this_geom, green_areas.geom)
     LIMIT 1 INTO cluster_id_match;

  IF cluster_id_match IS NULL THEN
     -- Create a new cluster
     INSERT INTO green_areas (ids, geom) VALUES (ARRAY[this_id], this_geom);
  ELSE
     -- Append line to existing cluster
     UPDATE green_areas SET geom = ST_Union(this_geom, geom),
                          ids = array_prepend(this_id, ids)
      WHERE green_areas.cluster_id = cluster_id_match;
  END IF;
END LOOP;

-- Iterate through the green_areas, combining green_areas that intersect each other
LOOP
    SELECT a.cluster_id, b.cluster_id FROM green_areas a, green_areas b 
     WHERE ST_Intersects(a.geom, b.geom)
       AND a.cluster_id < b.cluster_id
      INTO id_a, id_b;

    EXIT WHEN id_a IS NULL;
    -- Merge cluster A into cluster B
    UPDATE green_areas a SET geom = ST_Union(a.geom, b.geom), ids = array_cat(a.ids, b.ids)
      FROM green_areas b
     WHERE a.cluster_id = id_a AND b.cluster_id = id_b;

    -- Remove cluster B
    DELETE FROM green_areas WHERE cluster_id = id_b;
END LOOP;

-- [jm] Build areas from green_areas
UPDATE green_areas ga SET geom = ST_BuildArea(ga.geom);
DELETE FROM green_areas WHERE geom IS NULL;
ALTER TABLE green_areas DROP COLUMN ids;
END;
$procedure$

