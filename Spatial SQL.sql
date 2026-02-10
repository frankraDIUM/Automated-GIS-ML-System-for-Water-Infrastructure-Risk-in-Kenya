-- Spatial SQL – Service area coverage
-- 1. Create or replace a function to get population within buffer for a given point
CREATE OR REPLACE FUNCTION get_population_served(point_geom geometry, buffer_meters double precision)
RETURNS double precision AS $$
DECLARE
  pop_sum double precision;
BEGIN
  SELECT COALESCE(SUM((ST_SummaryStats(ST_Clip(rast, ST_Buffer(point_geom, buffer_meters / 111320.0)))) .sum), 0)
  INTO pop_sum
  FROM population_raster
  WHERE ST_Intersects(rast, ST_Buffer(point_geom, buffer_meters / 111320.0));

  RETURN pop_sum;
END;
$$ LANGUAGE plpgsql;


-- 2. Add the column to the full table
ALTER TABLE water_points
ADD COLUMN IF NOT EXISTS pop_served_500m double precision;

-- 3. Populate the column (this may take a while — 21k+ points, each calling ST_Buffer + ST_Clip + ST_SummaryStats)
-- You can run this in batches if it takes too long (e.g. LIMIT 5000 first to test)
UPDATE water_points w
SET pop_served_500m = get_population_served(w.geometry, 500)
WHERE pop_served_500m IS NULL;   -- only update missing values

-- Checks
SELECT COUNT(*) AS updated_count
FROM water_points
WHERE pop_served_500m IS NOT NULL;

SELECT wpdx_id, status_clean, pop_served_500m
FROM water_points
ORDER BY pop_served_500m DESC
LIMIT 5;


-- 4. Underserved zones & clustering
-- Run clustering on underserved points (full Kenya)
DROP TABLE IF EXISTS non_functional_points;

CREATE TABLE non_functional_points AS
SELECT
    wpdx_id,
    status_clean,
    lat_deg,
    lon_deg,
    pop_served_500m,
    install_year,
    geometry
FROM water_points
WHERE status_clean NOT IN ('Functional', 'Functional, not in use')
ORDER BY pop_served_500m ASC;

CREATE INDEX IF NOT EXISTS idx_non_functional_geom
ON non_functional_points USING GIST (geometry);

SELECT COUNT(*) AS non_functional_count FROM non_functional_points;


-- 5. Clustering
-- Add cluster column
ALTER TABLE non_functional_points
ADD COLUMN IF NOT EXISTS cluster_id integer;

-- Cluster (1 km eps, min 5 points)
-- Perform the clustering and update in one go
WITH clusters AS (
    SELECT 
        ctid,  -- system column to uniquely identify rows (important!)
        ST_ClusterDBSCAN(geometry, eps := 0.009, minpoints := 5) OVER () AS computed_cluster
    FROM non_functional_points
)
UPDATE non_functional_points n
SET cluster_id = c.computed_cluster
FROM clusters c
WHERE n.ctid = c.ctid;
);

-- View top clusters
SELECT 
    cluster_id,
    COUNT(*) AS cluster_size,
    AVG(pop_served_500m) AS avg_pop_served,
    STRING_AGG(DISTINCT status_clean, ', ') AS status_types,
    ST_AsText(ST_Centroid(ST_Collect(geometry))) AS cluster_center
FROM non_functional_points
WHERE cluster_id IS NOT NULL
GROUP BY cluster_id
ORDER BY cluster_size DESC
LIMIT 10;


-- How many points were clustered vs noise/outliers
SELECT 
    CASE WHEN cluster_id IS NULL THEN 'Noise/Outliers' ELSE 'Clustered' END AS type,
    COUNT(*) AS count
FROM non_functional_points
GROUP BY type;



-- Export clustered points (with cluster_id)
SELECT json_build_object(
    'type', 'FeatureCollection',
    'features', json_agg(
        json_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(geometry)::json,
            'properties', json_build_object(
                'wpdx_id', wpdx_id,
                'status_clean', status_clean,
                'pop_served_500m', pop_served_500m,
                'install_year', install_year,
                'cluster_id', cluster_id
            )
        )
    )
) AS geojson
FROM non_functional_points
WHERE cluster_id IS NOT NULL;



-- Export cluster centroids (one point per cluster with size & avg pop)
SELECT json_build_object(
    'type', 'FeatureCollection',
    'features', json_agg(
        json_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(centroid)::json,
            'properties', json_build_object(
                'cluster_id', cluster_id,
                'size', cluster_size,
                'avg_pop_served', avg_pop_served
            )
        )
    )
) AS geojson
FROM (
    SELECT 
        cluster_id,
        COUNT(*) AS cluster_size,
        ROUND(AVG(pop_served_500m)::numeric, 0) AS avg_pop_served,
        ST_Centroid(ST_Collect(geometry)) AS centroid
    FROM non_functional_points
    WHERE cluster_id IS NOT NULL
    GROUP BY cluster_id
) AS sub;



-- 6. ML preparation & modeling

COPY (
    SELECT 
        w.wpdx_id,
        w.lat_deg,
        w.lon_deg,
        w.status_clean,
        w.pop_served_500m,
        w.install_year,
        w.is_urban,
        w.water_source_clean,
        w.water_tech_clean,
        w.geometry,
        n.cluster_id
    FROM water_points w
    LEFT JOIN non_functional_points n ON w.wpdx_id = n.wpdx_id
) TO 'I:\GEO DATA ANALYSIS\Kenya Water\nairobi_water_project\water_points_ml_with_clusters.csv' 
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',');




COPY (
    SELECT 
        w.wpdx_id,
        w.lat_deg,
        w.lon_deg,
        w.status_clean,
        w.pop_served_500m,
        w.install_year,
        w.is_urban,
        w.water_source_clean,
        w.water_tech_clean,
        ST_AsText(w.geometry) AS geom_wkt,
        n.cluster_id
    FROM water_points w
    LEFT JOIN non_functional_points n ON w.wpdx_id = n.wpdx_id
) TO 'I:\GEO DATA ANALYSIS\Kenya Water\nairobi_water_project\water_points_ml_clean.csv'
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',');


