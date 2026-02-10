# Automated GIS-ML System for Water Infrastructure Risk in Kenya
This project builds an automated, end-to-end GIS and machine learning pipeline to analyze water point infrastructure risk across Kenya, with a focused application in Nairobi County. Interact on Kepler  [![View](https://img.shields.io/badge/View-Click%20Here-blue)](https://kepler.gl/demo/map?mapUrl=https://dl.dropboxusercontent.com/scl/fi/pclqq358c1ya1qahw0rh8/keplergl_z7vj22j.json?rlkey=vtjpcyfb02svs0tbebilc8xlh&dl=0)</button> . View on ArcGIS online: [![View](https://img.shields.io/badge/View-Click%20Here-blue)](https://arcg.is/14zWq00)</button>

## 1. Project Objective

The primary goal was to build a **scalable, automated geospatial and machine learning workflow** to assess water point infrastructure risks **across Kenya**, identifying patterns of non-functionality, underserved zones, and failure risk nationwide.

Nairobi County was designated as a **high-priority focus area** for:
- Targeted filtering of high-risk points
- Visualization of priority zones
- Actionable recommendations for urban WASH interventions

Key deliverables:
- Spatial SQL automation for service area coverage and clustering
- Predictive ML model for water point failure risk
- Interactive maps and GIS-ready exports
- Prioritization insights for rehabilitation and policy

## 2. Data Sources & Ingestion

**Datasets**:
- WPdx Kenya water points (CSV): 21,953 points with attributes (`status_clean`, `install_year`, `water_tech_clean`, `pop_served_500m`, `is_urban`, etc.) Time period of the dataset:01 January 2011 - 01 December 2024. Modified: 14 December 2025
- WorldPop 2020 population raster (`ken_ppp_2020.tif`): ~100 m gridded population counts
- GADM Kenya Admin Level 1 boundaries (shapefile): 47 counties, including Nairobi (`NAME_1 = 'Nairobi'`)

**Ingestion**:
- Water points → PostGIS table `water_points` (GeoPandas + `to_postgis`)
- Population raster → `population_raster` (`raster2pgsql`, tiled, SRID 4326)
- Admin boundaries → `admin_boundaries`
- Nairobi subset created via `ST_Intersects` → `water_points_nairobi` (~11 points initially, expanded with buffer to ~25)

All data processed in PostgreSQL/PostGIS.

## 3. Spatial Analysis & Automation (Kenya-wide)

**Nationwide workflows**:

1. **Service area coverage**  
   - PL/pgSQL function `get_population_served`: computes population within 500 m using `ST_Buffer`, `ST_Clip`, `ST_SummaryStats`  
   - Added `pop_served_500m` to full `water_points` table

2. **Clustering of non-functional points**  
   - Table `non_functional_points` (~15,232 rows)  
   - `ST_ClusterDBSCAN` (eps ≈ 1 km, minpoints = 5) → `cluster_id`  
   - Results: 10,273 clustered points; largest cluster = 196 points

3. **Cluster summarization**  
   - Per-cluster: size, avg `pop_served_500m`, centroid  
   - Exported as GeoJSON (`clusters_points.geojson`, `clusters_centroids.geojson`)

## 4. Machine Learning – Failure Risk Prediction (Kenya-wide)

**Target**: `is_non_functional` (1 = Non-Functional / Abandoned / dry season; 0 = Functional)

**Final model**: Hybrid XGBoost (combined features from iterative runs)

**Features** (30 after encoding):
- `pop_served_500m`, `age` (2026 – install_year), `in_cluster`, `cluster_size`, `cluster_avg_pop`, `dist_to_functional`
- One-hot encoded: `water_source_clean`, `water_tech_clean`, `is_urban`

**Performance** (test set):
- ROC AUC: **0.9735**
- Accuracy: 0.92
- Non-functional class: Precision 0.96, Recall 0.91, F1-score 0.94

**Top drivers** (feature importance):
1. water_tech_clean_Motorized Pump - Electric (dominant)
2. in_cluster
3. cluster_avg_pop
4. water_tech_clean_Public Tapstand
5. water_source_clean_Protected Well
6. cluster_size
7. dist_to_functional
8. age

**Interpretation**:
- Electric motorized pumps and public tapstands are the strongest failure predictors — likely due to power issues, high usage, and maintenance challenges.
- Spatial clustering (large clusters, high cluster population density) strongly elevates risk.
- Distance to nearest functional point and age are meaningful secondary factors.

**Risk scoring**:
- Failure probability computed for all points
- High-risk threshold (>85%) used nationally; Nairobi-specific filtering applied post-analysis

## 5. Nairobi County Focus & High-Risk Filtering

While the core analysis was conducted nationwide (to maximize data for clustering and modeling), Nairobi County was prioritized for targeted application:

- Total points in Nairobi approximate bounds (lon 36.60–37.10, lat -1.50 to -1.10): **259**
- Risk score distribution in Nairobi: mean ~0.064, max ~0.623 (much lower than national high-risk areas)
- Top risk points in Nairobi: mostly functional motorized pumps (age 17–36 years), with max risk ~0.623

**High-risk filtering**:
- Nationwide high-risk points (>50% threshold): ~13,014
- In Nairobi bounds (>50%): **2 points**
- Final Nairobi high-risk GeoJSON exported (`high_risk_nairobi.geojson`) for visualization and ArcGIS Online publishing

**Nairobi insight**:
- Nairobi shows significantly lower predicted failure risk compared to national averages — likely due to better access, newer infrastructure, or urban maintenance advantages.
- The few high-risk points are associated with motorized pumps — consistent with the national top driver.

## 6. Visualization & Deliverables

**Tools**: leafmap / Kepler.gl  
**Key outputs**:
- Clustered non-functional points (colored by cluster_id)
- Cluster centroids (size-scaled)
- High-risk points (nationwide + Nairobi subset) in red

**Exported files**:
- `clusters_points.geojson` & `clusters_centroids.geojson`
- `high_risk_points.geojson` (nationwide)
- `high_risk_nairobi.geojson` (Nairobi-focused)
- `master_water_risk_prioritization.csv` (full dataset with risk scores)

## 7. Conclusions

The project delivered a robust national-level analysis of water point risks in Kenya, with Nairobi County highlighted as a high-priority urban case study.

**Key findings**:
- Electric motorized pumps and public tapstands are the most failure-prone technologies
- Large non-functional clusters (especially in high-population areas) are major underserved zones
- Predictive model (AUC 0.9735) effectively identifies risk drivers
- Nairobi shows **lower overall risk** (mean ~0.064, max ~0.623) compared to national hotspots — likely reflecting urban advantages
