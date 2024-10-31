-- make_green_areas.sql
-- Identifies which paths lie inside green areas and labels them accordingly
-- Copyright (c) 2024 The MUSA micromobility project contributors
-- This file is part of the MUSA micromobility project

CREATE OR REPLACE FUNCTION public.calculate_heuristic_estimate(
    target_vertex integer, current_vertex integer
)
RETURNS double precision
LANGUAGE plpgsql
AS $function$
DECLARE
    target_point geometry;
    current_point geometry;
    heuristic_estimate float;
BEGIN
    -- Retrieve the geometry points for the target_vertex and the current_vertex
    SELECT ST_AsText(the_geom) INTO target_point FROM ways_vertices_pgr WHERE id = target_vertex;
    SELECT ST_AsText(the_geom) INTO current_point FROM ways_vertices_pgr WHERE id = current_vertex;

    -- Calculate the Euclidean distance between the two points
    SELECT ST_Distance(target_point::geography, current_point::geography) INTO heuristic_estimate;

    RETURN heuristic_estimate;
END;
$function$
