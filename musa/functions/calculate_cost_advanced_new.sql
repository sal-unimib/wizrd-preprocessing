CREATE OR REPLACE FUNCTION public.calculate_cost_advanced_new(
	profile_type text, 
	edge_distance double precision, -- TODO we need to use this
	time_cost numeric, 
	road_type text, 
	pm2 integer, 
	pm10 integer, 
	w_green double precision, 
	safe_param_active boolean, 
	traffic_param boolean, 
	distance_param boolean,
	air_pollution_param boolean, 
	green_param boolean)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    edge_weight numeric; -- Declare a variable to store the edge_weight
    -- distance_influence numeric := 1;
    safe_param numeric := 1; -- Declare a variable to store the safe_param
    pm2_param numeric; -- Declare a variable to store the pm2_param
    pm10_param numeric; -- Declare a variable to store the pm10_param
    green_param_value numeric := 1.0;
    worse_pm_param numeric := 1.0;
BEGIN

    --- default algorithm
    IF distance_param = TRUE THEN
        edge_weight := edge_distance;
    ELSE
    	edge_weight := time_cost;
    END IF;

    --- refract better this "safe_param" in a way to include diffrent type of profile
    IF safe_param_active IS TRUE THEN
        safe_param := CASE
            WHEN road_type = 'pedestrian' THEN 0.8
            WHEN road_type = 'footway' THEN 0.8
            WHEN road_type = 'cycleway' AND profile_type = 'micromobility' THEN 0.8
            ELSE 1
        END;
    END IF;
    
    -- Handle air pollution path param
    IF air_pollution_param IS TRUE THEN
        pm2_param := ROUND(pm2 / 500.0, 2);
        IF pm2_param < 0.01 THEN pm2_param := 0.01; END IF;
        pm10_param := ROUND(pm10 / 500.0, 2);
        IF pm10_param < 0.01 THEN pm10_param := 0.01; END IF;
        RAISE NOTICE 'pm2: %, pm2_param: %', pm2, pm2_param;
        RAISE NOTICE 'pm10: %, pm10_param: %', pm10, pm10_param;
        worse_pm_param := GREATEST(pm2_param, pm10_param); -- The worst air quality value
    END IF;
    
    --- parametro relativo alla preferenza di percorsi verdi
    IF green_param = TRUE THEN
        green_param_value := w_green;
        -- RAISE NOTICE 'Green param: %', green_param_value;
    END IF;

    -- RAISE NOTICE 'slope value: %', slope;
    -- RAISE NOTICE 'slope source_elevation: %', source_elevation;
    -- RAISE NOTICE 'slope target_elevation: %', target_elevation;

    edge_weight := edge_weight * safe_param * green_param_value * worse_pm_param;

    RETURN edge_weight;
END;
$function$

