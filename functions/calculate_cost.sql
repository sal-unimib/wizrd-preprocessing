-- calculate_cost.sql
-- Computes a way's cost according to several parameters
-- Copyright (c) 2024 Jacopo Maltagliati (j.maltagliati@campus.unimib.it)
-- Copyright (c) 2024 Matteo Vaghi
-- Copyright (c) 2024 The MUSA micromobility project contributors
-- This file is part of the MUSA micromobility project

CREATE OR REPLACE FUNCTION public.calculate_cost(
    id BIGINT,
    profile_type TEXT,
    pm2_col TEXT,
    traffic_col TEXT,
    params HSTORE,
    distance DOUBLE PRECISION,
    road_type TEXT,
    maxspeed DOUBLE PRECISION,
    green BOOLEAN,
    surface TEXT,
    one_way INTEGER,
    pm2 INTEGER,
    traffic INTEGER
)
RETURNS TABLE(cost DOUBLE PRECISION, reverse_cost DOUBLE PRECISION)
LANGUAGE plpgsql
AS $function$
DECLARE
    safe_score DOUBLE PRECISION := 1.0;
    pm2_score DOUBLE PRECISION := 1.0;
    traffic_score DOUBLE PRECISION := 1.0;
    green_score DOUBLE PRECISION := 1.0;
    user_score DOUBLE PRECISION := 1.0;
    --
    rough_surface BOOLEAN := FALSE;
    pedestrian_road BOOLEAN := FALSE;
    cycling_road BOOLEAN := FALSE;
    --
    is_air_quality BOOLEAN := params->'air_quality';
    is_distance BOOLEAN := params->'distance';
    is_green BOOLEAN := params->'green';
    is_safe BOOLEAN := params->'safe';
    is_traffic BOOLEAN := params->'traffic';
    is_reduced_mobility BOOLEAN  := params->'reduced_mobility';
    --
BEGIN
    cost := 0.0;
    reverse_cost := 0.0;

    IF road_type IN ('ground', 'gravel', 'dirt', 'unpaved') THEN
        rough_surface := TRUE;
    END IF;

    IF road_type IN ('footway', 'footpath', 'pedestrian', 'steps', 'foot_crossing') THEN
        pedestrian_road := TRUE;
    END IF;

    IF road_type IN ('cycleway', 'cycle_crossing') THEN
       cycling_road = TRUE;
    END IF;

    IF is_reduced_mobility THEN
        IF rough_surface OR road_type = 'steps' THEN
            cost := -1.0; -- Reduced mobility users cannot use these
        END IF;
    END IF;

    -- pedestrians should stick to footways
    IF profile_type = 'pedestrian' THEN
    	IF pedestrian_road IS FALSE THEN
            -- but service and residential roads often don't have
            -- marked footways and can be (quite) safely used by peds
            IF road_type IN ('residential', 'service') THEN
                user_score := 1.1;
            ELSE
                user_score := 5.0;
            END IF;
        END IF;
    ELSE -- <=> profile_type IN ('bike', 'ebike', 'scooter')
        IF cycling_road IS FALSE THEN
            -- bikes and co. should avoid footways where possible...
            IF pedestrian_road IS TRUE THEN
                user_score := 5.0;
            -- ...except for green areas, where bikes are (mostly) allowed...
            ELSEIF road_type IN ('footway', 'footpath') AND green IS TRUE THEN
                user_score := 1.1;
            ELSE
                user_score := 1.2;
            END IF;
        END IF;
        -- e-scooters should avoid rough roads
        IF (profile_type = 'scooter' AND rough_surface IS TRUE) THEN
            user_score := 5.0;
        END IF;
    END IF;

    -- safe_score -> avoid high-speed roads
    -- TODO integrate Walkability Index metrics
    IF is_safe IS TRUE THEN
        safe_score := CASE
            WHEN maxspeed <= 30.0 THEN 0.5
            WHEN maxspeed > 30 AND maxspeed <= 50 THEN 0.7
            WHEN maxspeed > 50 AND maxspeed <= 70 THEN 1.0
            ELSE 5.0
        END;
    END IF;

    -- Handle traffic param
    -- TODO Integrate TomTom Dataset
    IF is_traffic IS TRUE THEN
        traffic_score := 1.0 - ROUND(traffic / 4.0, 2);
        IF traffic_score < 0.01 THEN traffic_score := 0.01; END IF;
        traffic_score := 1 / traffic_score;
        -- Avoid accidents
        IF pedestrian_road IS FALSE AND traffic > 4 THEN
            cost := -1.0; -- REALLY avoid accidents
        END IF;
    END IF;

    -- Handle air pollution param
    IF is_air_quality IS TRUE THEN
        pm2_score := ROUND(pm2 / 500.0, 2);
        IF pm2_score < 0.01 THEN pm2_score := 0.01; END IF;
    END IF;

    -- give worse score for non-green areas if we're looking for green paths
    IF is_green IS TRUE AND green IS FALSE THEN
        green_score := 2.0;
    END IF;

    IF cost >= 0.0 THEN
       -- Usable
        cost := distance *
            user_score *
            safe_score *
            green_score *
            traffic_score *
            pm2_score;
        reverse_cost := cost * one_way;
    ELSE
        -- Not usable
        reverse_cost := cost;
    END IF;

    /*
    RAISE NOTICE 'user_score: %', user_score;
    RAISE NOTICE 'distance: %', distance;
    RAISE NOTICE 'traffic_score: %', traffic_score;
    RAISE NOTICE 'safe_score: %', safe_score;
    RAISE NOTICE 'green_score: %', green_score;
    RAISE NOTICE 'cost: %', cost;
    RAISE NOTICE 'reverse_cost: %', reverse_cost;
    */

    RETURN QUERY SELECT cost, reverse_cost;
END;
$function$
