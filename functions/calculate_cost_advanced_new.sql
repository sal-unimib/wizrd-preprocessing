CREATE OR REPLACE FUNCTION public.calculate_cost_advanced_new(
    profile_type text, 
    edge_distance double precision, 
    time_cost numeric, 
    road_type text, 
    pm2 integer, 
    pm10 integer,
    traffic integer,
    maxspeed_forward double precision,
    green boolean,
    surface text,
    is_air_quality boolean,
    is_distance boolean,
    is_green boolean,
    is_safe boolean,
    is_traffic boolean)
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
    user_param numeric := 1.0;
    rough_surface boolean := FALSE;
    pedestrian_road boolean := FALSE;
BEGIN

    IF surface IN ('ground', 'gravel', 'dirt', 'unpaved') THEN
        rough_surface := TRUE;
    END IF;

    IF road_type IN ('footway', 'footpath', 'steps', 'crossing') THEN
        pedestrian_road := TRUE;
    END IF;

    -- default algorithm
    IF is_distance = TRUE THEN
        edge_weight := edge_distance;
    ELSE
    	edge_weight := time_cost;
    END IF;

    -- pedestrians should stick to footways
    IF profile_type = 'pedestrian' AND pedestrian_road IS FALSE THEN
        user_param := 10.0;
    ELSE -- <=> profile_type IN ('bike', 'ebike', 'scooter')
        -- bikes and co. should prefer cycling roads and avoid footways...
        IF road_type = 'cycleway' THEN
            user_param := 0.5;
        -- ...except for green areas, where bikes are (mostly) allowed...
        ELSEIF road_type IN ('footway', 'footpath') AND green IS TRUE THEN
            user_param := 1.0;
        -- ..but bikes should always avoid steps
        ELSEIF road_type = 'steps' THEN
            user_param := 10.0;
        END IF;
    END IF;

    -- e-scooters should not choose rough roads
    IF (profile_type = 'scooter' AND rough_surface IS TRUE) THEN
        user_param := 10.0;
    END IF;

    -- refract better this "safe_param" in a way to include diffrent type of profile
    IF is_safe IS TRUE THEN -- QUESTA CONDIZIONE VA MODIFICATA IN BASE AL TIPO DI MEZZO 
        safe_param := CASE
            /*
            WHEN road_type = 'pedestrian' THEN 0.7
            WHEN road_type = 'living_street' THEN 0.8
            WHEN road_type = 'footway' THEN 0.7
            WHEN road_type = 'residential' THEN 0.8
            WHEN road_type = 'track' THEN 0.7
            WHEN road_type = 'steps' AND profile_type = 'pedestrian' THEN 0.7
            WHEN road_type = 'cycleway' AND profile_type = 'micromobility' THEN 0.7
            WHEN road_type = 'cycleway' THEN 0.8
            ELSE 1.0*/
            WHEN maxspeed_forward <= 30.0 THEN 0.5
            WHEN maxspeed_forward > 30 AND maxspeed_forward <= 50 THEN 0.7
            WHEN maxspeed_forward > 50 AND maxspeed_forward <= 70 THEN 1.0
            ELSE 10.0
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

    edge_weight := ((edge_weight * user_param) / traffic_param) * safe_param * green_param * worse_pm_param;

    RAISE NOTICE 'edge_weight after: %', edge_weight;

    RETURN edge_weight;
END;
$function$

