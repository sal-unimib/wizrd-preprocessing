CREATE OR REPLACE FUNCTION public.calculate_time_cost(profile_type text, edge_distance double precision, baseline_speed numeric, generalized_congestion text, source_elevation numeric, target_elevation numeric, pavement_quality character varying, road_type character varying, distance_param boolean, traffic_param boolean)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    time_cost numeric;
    original_slope numeric := (source_elevation - target_elevation) / (edge_distance * 1000);
    congestion_numeric numeric;
    pavement_quality_numeric numeric;
    slope numeric;
BEGIN
    -- Default algorithm
    IF distance_param = TRUE THEN
        time_cost := (edge_distance / baseline_speed);
        RETURN time_cost;
    END IF;

    -- Pendeza
    slope := CASE
        WHEN original_slope >= -5 AND original_slope < -10 THEN 1.1
        WHEN original_slope > -10 AND original_slope < -5 THEN 1.5
        WHEN original_slope >= 5 AND original_slope < 15 THEN 0.9
        WHEN original_slope >= 15 THEN 0.9
        ELSE 1.0
    END;

    -- Check sulla tipologia della strada
    pavement_quality_numeric := CASE
        WHEN profile_type = 'micromobility' AND road_type IN ('steps', 'path') THEN 0.27
        WHEN profile_type = 'micromobility' AND road_type = 'cycleway' THEN 1.1 
        WHEN profile_type = 'micromobility' AND road_type IN ('motorway', 'motorway_link', 'trunk', 'trunk_link') THEN 0.001
        ELSE 1.0
    END;

    -- Check sulla qualità del terreno
    IF pavement_quality_numeric != 0.27 AND pavement_quality_numeric != 0.001 THEN
        pavement_quality_numeric := CASE
            WHEN pavement_quality = 'gravel' AND profile_type = 'micromobility' THEN 0.9
            WHEN pavement_quality = 'sett' AND profile_type = 'micromobility' THEN 0.5
            WHEN pavement_quality = 'unpaved' AND profile_type = 'micromobility' THEN 0.8
            WHEN pavement_quality = 'fine_gravel' AND profile_type = 'micromobility' THEN 0.9
            WHEN pavement_quality = 'compacted' AND profile_type = 'micromobility' THEN 0.9
            WHEN pavement_quality = 'paving_stones' AND profile_type = 'micromobility' THEN 0.8
            WHEN pavement_quality = 'ground' AND profile_type = 'micromobility' THEN 0.8
            ELSE 1.0
        END;
    END IF;

    -- Parametro relativo al traffico
    IF traffic_param = TRUE THEN
        congestion_numeric := CASE
            WHEN generalized_congestion = 'incident' THEN 0.2
            WHEN generalized_congestion = 'congested' THEN 0.4
            WHEN generalized_congestion = 'moderate' THEN 0.5
            WHEN generalized_congestion = 'light' THEN 0.8
            ELSE 1.0
        END;
    ELSE
        congestion_numeric := 1; -- Handle traffic param when it is FALSE
    END IF;

    -- Handle possible division by zero
    IF baseline_speed = 0 THEN
        baseline_speed := 1;
    END IF;

    IF congestion_numeric = 0 THEN
        congestion_numeric := 1;
    END IF;

    IF pavement_quality = '' THEN
        pavement_quality_numeric := 1;
    END IF;

    -- Time cost estimation in seconds
    time_cost := (edge_distance * 1000 / ((baseline_speed / 3.6) * congestion_numeric * slope * pavement_quality_numeric));

    RETURN time_cost;
END;
$function$

