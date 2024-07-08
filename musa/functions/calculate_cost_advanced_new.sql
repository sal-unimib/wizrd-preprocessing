CREATE OR REPLACE FUNCTION public.calculate_cost_advanced_new(profile_type text, edge_distance double precision, time_cost numeric, road_type character varying, pm2_air_path_quality text, pm10_air_path_quality text, w_green numeric, safe_param_active boolean, traffic_param boolean, distance_param boolean, air_pollution_param boolean, green_param boolean)
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
        edge_weight := time_cost * safe_param * green_param_value * worse_pm_param;
        RETURN edge_weight;
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
        pm2_param := CASE  
            WHEN pm2_air_path_quality = 'good' THEN 0.2
            WHEN pm2_air_path_quality = 'fair' THEN 0.4
            WHEN pm2_air_path_quality = 'moderate' THEN 0.5
            WHEN pm2_air_path_quality = 'poor' THEN 0.7
            WHEN pm2_air_path_quality = 'very_poor' THEN 0.9
            ELSE 1.0 -- extremly poor
        END;

        pm10_param := CASE  
            WHEN pm10_air_path_quality = 'good' THEN 0.2
            WHEN pm10_air_path_quality = 'fair' THEN 0.4
            WHEN pm10_air_path_quality = 'moderate' THEN 0.5
            WHEN pm10_air_path_quality = 'poor' THEN 0.7
            WHEN pm10_air_path_quality = 'very_poor' THEN 0.9
            ELSE 1.0 -- extremly poor
        END;

        worse_pm_param := GREATEST(pm2_param, pm10_param); -- The worst air quality value
    END IF;
    
    --- parametro relativo alla preferenza di percorsi verdi
    IF green_param = TRUE THEN
        green_param_value := w_green;
        -- RAISE NOTICE 'Green param: %', green_param_value;
    END IF;

    -- handle edge cases
    IF safe_param_active = FALSE THEN
        safe_param = 1;
    END IF;

    IF green_param = FALSE THEN
        green_param_value = 1;
    END IF;

    IF air_pollution_param = FALSE THEN
        worse_pm_param = 1;
    END IF;
    
    -- possibilità di inserire i commenti in console sul database
    -- RAISE NOTICE 'Air pollution param: %', air_pollution_param;
    -- RAISE NOTICE 'worse_pm_param: %', worse_pm_param;
    -- RAISE NOTICE 'pm10_param: %', pm10_param;
    -- RAISE NOTICE 'pm2_param: %', pm2_param;
    -- RAISE NOTICE 'slope value: %', slope;
    -- RAISE NOTICE 'slope source_elevation: %', source_elevation;
    -- RAISE NOTICE 'slope target_elevation: %', target_elevation;


    -- Cost personilized function
    edge_weight := time_cost * safe_param * green_param_value * worse_pm_param;

    RETURN edge_weight;
END;
$function$

