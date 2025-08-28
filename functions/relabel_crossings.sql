-- relabel_crossings.sql
-- Changes the 'highway' label of crossings
-- Copyright (c) 2024 Jacopo Maltagliati (j.maltagliati@campus.unimib.it)
-- This file is part of the MUSA micromobility project

-- XXX [jm] This procedure uses the 'tags' column in 'osm_ways' so 
--          osm2pgrouting needs to be called with the --addnodes flag

CREATE OR REPLACE PROCEDURE public.relabel_crossings()
LANGUAGE plpgsql
AS $procedure$

DECLARE fcids BIGINT[];
DECLARE ccids BIGINT[];
BEGIN

fcids := array(
    SELECT osm_id FROM osm_ways WHERE tags->'footway' LIKE 'crossing' 
    );

ccids := array(
    SELECT osm_id FROM osm_ways WHERE tags->'cycleway' LIKE 'crossing' 
    );

UPDATE ways 
    SET highway = 'foot_crossing' 
    WHERE osm_id =ANY(fcids);
    
UPDATE ways 
    SET highway = 'cycle_crossing' 
    WHERE osm_id =ANY(ccids);

END;
$procedure$
