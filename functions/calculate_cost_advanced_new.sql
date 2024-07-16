CREATE OR REPLACE FUNCTION public.calculate_cost_advanced_new(
    profile_type text, 
    edge_distance double precision, 
    time_cost numeric, 
    road_type text, 
    pm2 integer, 
    pm10 integer,
    traffic integer,
    green boolean, 
    is_safe boolean, 
    is_traffic boolean, 
    is_distance boolean, 
    is_air_quality boolean, 
    is_green boolean)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    -- Local variables
    edge_weight numeric;
    safe_param numeric := 1.0;
    pm2_param numeric := 1.0;
    pm10_param numeric := 1.0;
    worse_pm_param numeric := 1.0;
    traffic_param numeric := 1.0; 
    green_param numeric := 1.0;
BEGIN

    -- default algorithm
    IF is_distance = TRUE THEN
        edge_weight := edge_distance;
    ELSE
    	edge_weight := time_cost;
    END IF;

    -- refract better this "safe_param" in a way to include diffrent type of profile
    IF is_safe IS TRUE THEN
        safe_param := CASE
            WHEN road_type = 'pedestrian' THEN 0.7
            WHEN road_type = 'living_street' THEN 0.8
            WHEN road_type = 'footway' THEN 0.7
            WHEN road_type = 'residential' THEN 0.8
            WHEN road_type = 'track' THEN 0.7
            WHEN road_type = 'steps' AND profile_type = 'pedestrian' THEN 0.7
            WHEN road_type = 'cycleway' AND profile_type = 'micromobility' THEN 0.7
            WHEN road_type = 'cycleway' THEN 0.8
            ELSE 1.0
        END;
    END IF;

    -- Handle traffic param
    IF is_traffic IS TRUE THEN
        traffic_param := 1.0 - ROUND(traffic / 4.0, 2);
        IF traffic_param < 0.01 THEN traffic_param := 0.01; END IF;
    END IF;
    
    -- Handle air pollution param
    IF is_air_quality IS TRUE THEN
        pm2_param := ROUND(pm2 / 500.0, 2);
        IF pm2_param < 0.01 THEN pm2_param := 0.01; END IF;
        pm10_param := ROUND(pm10 / 500.0, 2);
        IF pm10_param < 0.01 THEN pm10_param := 0.01; END IF;
        RAISE NOTICE 'pm2: %, pm2_param: %', pm2, pm2_param;
        RAISE NOTICE 'pm10: %, pm10_param: %', pm10, pm10_param;
        worse_pm_param := GREATEST(pm2_param, pm10_param); -- The worst air quality value
    END IF;

    -- parametro relativo alla preferenza di percorsi verdi
    IF is_green IS TRUE AND green IS TRUE THEN
        -- TODO [jm] Weight based on surface type?
        green_param := 0.5;
    END IF;

    RAISE NOTICE 'edge_weight before: %', edge_weight;
    RAISE NOTICE 'traffic_param: %', traffic_param;
    RAISE NOTICE 'safe_param: %', safe_param;
    RAISE NOTICE 'green_param: %', green_param;
    RAISE NOTICE 'worse_pm_param: %', worse_pm_param;
    -- RAISE NOTICE 'slope value: %', slope;
    -- RAISE NOTICE 'slope source_elevation: %', source_elevation;
    -- RAISE NOTICE 'slope target_elevation: %', target_elevation;

    edge_weight := (edge_weight / traffic_param) * safe_param * green_param * worse_pm_param;

    RAISE NOTICE 'edge_weight after: %', edge_weight;

    RETURN edge_weight;
END;
$function$

