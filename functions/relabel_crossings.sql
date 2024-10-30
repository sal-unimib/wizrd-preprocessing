-- relabel_crossings.sql
-- Changes the 'highway' label of crossings from 'footway' to 'crossing'
-- Copyright (c) 2024 Jacopo Maltagliati (j.maltagliati@campus.unimib.it)
-- This file is part of the MUSA micromobility project

-- XXX [jm] This procedure uses the 'tags' column in 'osm_nodes' so 
--          osm2pgrouting needs to be called with the --addnodes flag

CREATE OR REPLACE PROCEDURE public.relabel_crossings()
LANGUAGE plpgsql
AS $procedure$

DECLARE crossing_ids BIGINT[];
BEGIN

crossing_ids := array(
    SELECT osm_id FROM osm_nodes WHERE tags->'highway' LIKE 'crossing' 
    );

UPDATE ways 
    SET highway = 'crossing' 
    WHERE highway IN ('footway', 'footpath') 
        AND source_osm =ANY(crossing_ids)  
        AND target_osm =ANY(crossing_ids);

END;
$procedure$
