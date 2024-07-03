CREATE OR REPLACE FUNCTION public.calculate_cost_advanced(profile_type text, edge_distance double precision, baseline_speed numeric, generalized_congestion text, source_elevation numeric, target_elevation numeric, pavement_quality character varying, road_type character varying, pm2_air_path_quality text, pm10_air_path_quality text, leisure character varying, amenity character varying, landuse character varying, natural_link character varying, tourism character varying, safe_param_active boolean, traffic_param boolean, distance_param boolean, air_pollution_param boolean, green_param boolean)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    edge_weight numeric; -- Declare a variable to store the edge_weight
    -- distance_influence numeric := 1;
    safe_param numeric := 1; Declare -- Declare a variable to store the safe_param
    pm2_param numeric; -- Declare a variable to store the pm2_param
    pm10_param numeric; -- Declare a variable to store the pm10_param
    slope numeric := (source_elevation - target_elevation) / (edge_distance * 1000); -- Calculate the slope percentage
    congestion_numeric numeric; -- Declare a variable to store the numeric value of generalized_congestion
    pavement_quality_numeric numeric; -- Declare a variable to store the numeric value of pavement_quality
    green_param_value numeric := 1.0; -- Capire se il valore va bene (dirlo magari effettuando qualche test e riportandolo all'interno della tesi) TODO
    worse_pm_param numeric := 1.0;

    leisure_value numeric := 1; -- Declare a variable to store the leisure_value
    amenity_value numeric := 1; -- Declare a variable to store the amenity_value
    landuse_value numeric := 1; -- Declare a variable to store the landuse_value
    natural_link_value numeric := 1; -- Declare a variable to store the natural_link_value
    tourism_value numeric := 1; -- Declare a variable to store the tourism_value
BEGIN

    IF distance_param = TRUE THEN
        edge_weight := (edge_distance / baseline_speed) * safe_param * green_param_value * worse_pm_param;
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

    slope := CASE
        WHEN slope >= -5 AND slope < -10 THEN 1.1
        WHEN slope > -10 AND slope < -5 THEN 1.5
        WHEN slope >= 5 AND slope < 15 THEN 0.9
        WHEN slope >= 15 THEN 0.9
        ELSE 1.0
    END;

    -- check sulla tipologia della strada
    pavement_quality_numeric := CASE
        -- aggiungere la variabile road_type nella formula ???
        WHEN profile_type = 'micromobility' AND road_type IN ('steps', 'path') THEN 0.27
        WHEN profile_type = 'micromobility' AND road_type = 'cycleway' THEN 1.1 
        WHEN profile_type = 'micromobility' AND road_type IN ('motorway', 'motorway_link', 'trunk', 'trunk_link') THEN 0.0

        ELSE 1.0
    END;

    -- check sulla qualità del terreno
    IF pavement_quality_numeric != 0.27 AND pavement_quality_numeric != 0.0 THEN
        pavement_quality_numeric := CASE
                -- aggiungere controllo sul profile type? Questo eprché i pedoni non sono affetti dalla velocità
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

    IF traffic_param IS TRUE THEN
        congestion_numeric := CASE
            WHEN generalized_congestion = 'incident' THEN 0.2
            WHEN generalized_congestion = 'congested' THEN 0.4
            WHEN generalized_congestion = 'moderate' THEN 0.5
            WHEN generalized_congestion = 'light' THEN 0.8
            ELSE 1.0
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

    IF green_param IS TRUE THEN
        leisure_value := CASE leisure
            WHEN 'park' THEN 0.7
            WHEN 'nature_reserve' THEN 0.7
            WHEN 'garden' THEN 0.7
            WHEN 'playground' THEN 0.7
            ELSE 1.0
        END;

        amenity_value := CASE amenity
            WHEN 'grave_yard' THEN 0.9
            ELSE 1.0
        END;

        landuse_value := CASE landuse
            WHEN 'allotments' THEN 0.8
            WHEN 'cemetery' THEN 0.8
            WHEN 'farmland' THEN 0.8
            WHEN 'forest' THEN 0.8
            WHEN 'grass' THEN 0.8
            WHEN 'greenfield' THEN 0.8
            WHEN 'meadow' THEN 0.8
            WHEN 'orchard' THEN 0.8
            WHEN 'recreation_ground' THEN 0.8
            WHEN 'village_green' THEN 0.8
            WHEN 'vineyard' THEN 0.8
            ELSE 1.0
        END;

        natural_link_value := CASE natural_link
            WHEN 'wood' THEN 0.8
            WHEN 'scrub' THEN 0.8
            WHEN 'heath' THEN 0.8
            WHEN 'grassland' THEN 0.8
            WHEN 'wetland' THEN 0.8
            ELSE 1.0
        END;

        tourism_value := CASE tourism
            WHEN 'camp_site' THEN 0.9
            ELSE 1.0
        END;

        -- retrive the gratest
        green_param_value := LEAST(leisure_value, amenity_value, landuse_value, natural_link_value, tourism_value); -- The worst air quality value
        -- RAISE NOTICE 'Green param: %', green_param_value;
    END IF;



    -- Handle traffic path param
    IF traffic_param = FALSE THEN
        congestion_numeric = 1;
    END IF;

    IF safe_param_active = FALSE THEN
        safe_param = 1;
    END IF;

    IF green_param = FALSE THEN
        green_param_value = 1;
    END IF;

    IF air_pollution_param = FALSE THEN
        worse_pm_param = 1;
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


    -- RAISE NOTICE 'Air pollution param: %', air_pollution_param;
    -- RAISE NOTICE 'worse_pm_param: %', worse_pm_param;
    -- RAISE NOTICE 'pm10_param: %', pm10_param;
    -- RAISE NOTICE 'pm2_param: %', pm2_param;
    -- RAISE NOTICE 'slope value: %', slope;
    -- RAISE NOTICE 'slope source_elevation: %', source_elevation;
    -- RAISE NOTICE 'slope target_elevation: %', target_elevation;


    -- Cost personilized function
    edge_weight := (edge_distance / (baseline_speed * congestion_numeric * slope * pavement_quality_numeric)) * safe_param * green_param_value * worse_pm_param;

    -- simple dijkstra distance route calculation 
    -- IF distance_param = TRUE THEN
    --     edge_weight := (edge_distance / baseline_speed) * safe_param * green_param_value * worse_pm_param;
    -- END IF;
    RETURN edge_weight;
END;
$function$

