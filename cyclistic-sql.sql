--prepare phase

--verify data
SELECT *
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025` 
LIMIT 10;

SELECT COUNT(*) AS total_rows
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025`;

SELECT *
FROM `your-project-id.cyclistic.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'tripdata_2025';

--sort and filter to understand the data and verify the import was successful
SELECT 
  ride_id,
  started_at,
  ended_at,
  member_casual
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025`
ORDER BY started_at DESC
LIMIT 20;

SELECT 
  ride_id,
  started_at,
  ended_at,
  member_casual
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025`
ORDER BY started_at ASC
LIMIT 20;

SELECT *
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025`
WHERE member_casual = "member"
LIMIT 20;

SELECT 
  member_casual,
  COUNT(*) AS rides
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025`
GROUP BY member_casual;

--process phase

--create a new table for cleaning
CREATE OR REPLACE TABLE 
  `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
AS
SELECT * 
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025`;

SELECT
  COUNT(*) AS total_rows 
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`;

--check for duplicates
SELECT
  ride_id,
  COUNT(*) AS duplicates
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
GROUP BY ride_id
HAVING COUNT(*) > 1;

--remove duplicates
CREATE OR REPLACE TABLE
  `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
AS
SELECT *
FROM(
  SELECT *,
  ROW_NUMBER() OVER(
    PARTITION BY ride_id
    ORDER BY started_at
  ) AS row_num
  FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
)
WHERE row_num=1;

--check for missing values
SELECT
  COUNTIF(ride_id IS NULL) AS ride_id_nulls,
  COUNTIF(rideable_type IS NULL) AS rideable_type_nulls,
  COUNTIF(started_at IS NULL) AS started_at_nulls,
  COUNTIF(ended_at IS NULL) AS ended_at_nulls,
  COUNTIF(start_station_name IS NULL) AS start_station_name_nulls,
  COUNTIF(end_station_name IS NULL) AS end_station_name_nulls,
  COUNTIF(member_casual IS NULL) AS member_casual_nulls
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`;

--remove critical null rows
CREATE OR REPLACE TABLE
  `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
AS
SELECT *
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
WHERE
  ride_id IS NOT NULL
  AND rideable_type IS NOT NULL
  AND started_at IS NOT NULL
  AND ended_at IS NOT NULL
  AND member_casual IS NOT NULL;

--calculate ride length
SELECT
  ride_id,
  TIMESTAMP_DIFF(ended_at, started_at, MINUTE) AS ride_length
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`;

--detect impossible ride lengths
SELECT
  MIN(TIMESTAMP_DIFF(ended_at, started_at, MINUTE)) AS min_ride_length,
  MAX(TIMESTAMP_DIFF(ended_at, started_at, MINUTE)) AS max_ride_length
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`;

--remove negative or zero ride lengths
CREATE OR REPLACE TABLE `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
AS
SELECT *
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
WHERE TIMESTAMP_DIFF(ended_at, started_at, SECOND) > 0;

--inspect distribution of long rides to see if they're genuine or anomalies. i will keep ride lengths between 1 and 1440 minutes because rides under 1 minute are likely false start or test rides, and rides over 24 hours are lost bikes or unusual cases that would distort averages.
SELECT
  APPROX_QUANTILES(TIMESTAMP_DIFF(ended_at, started_at, MINUTE), 100) AS percentiles
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`;

--create final cleaned table
CREATE OR REPLACE TABLE `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
AS
SELECT
  ride_id,
  rideable_type,
  started_at,
  ended_at,
  TIMESTAMP_DIFF(ended_at, started_at, MINUTE) AS ride_length_minutes,
  EXTRACT(DATE FROM started_at) AS ride_date,
  EXTRACT(YEAR FROM started_at) AS ride_year,
  EXTRACT(MONTH FROM started_at) AS ride_month,
  FORMAT_DATE('%B', DATE(started_at)) AS month_name,
  EXTRACT(DAYOFWEEK FROM started_at) AS day_of_week_num,
  FORMAT_DATE('%A', DATE(started_at)) AS day_of_week,
  EXTRACT(HOUR FROM started_at) AS start_hour,
  CASE
    WHEN EXTRACT(DAYOFWEEK FROM started_at) IN (1,7) THEN 'Weekend'
    ELSE 'Weekday'
  END AS weekday_type,
  CASE
    WHEN EXTRACT(MONTH FROM started_at) IN (12, 1, 2) THEN 'Winter'
    WHEN EXTRACT(MONTH FROM started_at) IN (3, 4, 5) THEN 'Spring'
    WHEN EXTRACT(MONTH FROM started_at) IN (6, 7, 8) THEN 'Summer'
    WHEN EXTRACT(MONTH FROM started_at) IN (9, 10, 11) THEN 'Fall'
  END AS season,
  start_station_name,
  start_station_id,
  end_station_name,
  end_station_id,
  start_lat,
  start_lng,
  member_casual
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
WHERE
  ride_id IS NOT NULL
  AND rideable_type IS NOT NULL
  AND started_at IS NOT NULL
  AND ended_at IS NOT NULL
  AND member_casual IS NOT NULL
  AND TIMESTAMP_DIFF(ended_at, started_at, MINUTE) BETWEEN 1 AND 1440
QUALIFY
  ROW_NUMBER() OVER(
    PARTITION BY ride_id
    ORDER BY started_at
  ) = 1;

--confirm the cleaned table works
SELECT COUNT(*) AS total_rows
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`;

--validate ride length
SELECT 
  MIN(ride_length_minutes) AS min_ride_length,
  MAX(ride_length_minutes) AS max_ride_length,
  AVG(ride_length_minutes) AS avg_ride_length
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`;

--validate dates
SELECT 
  MIN(ride_date) AS earliest_ride_date,
  MAX(ride_date) AS latest_ride_date,
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`;

--analyze phase

--find out how many rides were taken by members vs casual riders
--finding: members account for more total rides
SELECT
  member_casual,
  COUNT(*) AS total_rides,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS total_percent
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
GROUP BY member_casual
ORDER BY total_rides DESC;

--find out which member type takes the longer rides
--finding: casual riders use bikes for longer leisure rides while members use them for shorter, routine transportation
SELECT
  member_casual,
  COUNT(*) AS total_rides,
  ROUND(AVG(ride_length_minutes), 2) AS avg_ride_length,
  APPROX_QUANTILES(ride_length_minutes, 100)[OFFSET(50)] AS median_ride_length,
  MIN(ride_length_minutes) AS min_ride_length,
  MAX(ride_length_minutes) AS max_ride_length
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
GROUP BY member_casual;

--find out how much ridership varies by month
--finding: this shows seasonality. casual riders tend to ride more in the warmer months, while members tend to ride more consistently throughout the year. 
SELECT
  ride_month,
  month_name,
  member_casual,
  COUNT(*) AS total_rides,
  ROUND(AVG(ride_length_minutes), 2) AS avg_ride_length
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
GROUP BY ride_month, month_name, member_casual
ORDER BY ride_month, member_casual;

--find out how ridership varies by day of week
--finding: this shows that casual riders concentrate on weekends and members ride more during the workweek.
SELECT 
  day_of_week_num,
  day_of_week,
  member_casual,
  COUNT(*) AS total_rides,
  ROUND(AVG(ride_length_minutes), 2) AS avg_ride_length
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
GROUP BY day_of_week_num, day_of_week, member_casual
ORDER BY day_of_week_num, member_casual;

--find out weekday vs weekend behavior
--finding: members are twice as likely than casual riders to ride during the weekday. during the weekend, both members and casual riders ride about the same frequency. On average, casual riders ride longer than members.
SELECT 
  weekday_type,
  member_casual,
  COUNT(*) AS total_rides,
  ROUND(AVG(ride_length_minutes), 2) AS avg_ride_length
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
GROUP BY weekday_type, member_casual
ORDER BY weekday_type, member_casual;

--find out how ridership varies by time of day
--finding: members peak around morning and evening commute hours, while casual riders may peak later in the day.
SELECT 
  start_hour,
  member_casual,
  COUNT(*) AS total_rides,
  ROUND(AVG(ride_length_minutes), 2) AS avg_ride_length
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
GROUP BY start_hour, member_casual
ORDER BY start_hour, member_casual;

--find out what bike type each group prefers
--finding: almost twice as many casual riders and members prefer to ride eletric bike over classic bikes
SELECT 
  rideable_type,
  member_casual,
  COUNT(*) AS total_rides,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY member_casual), 2) AS percent_within_rider_type
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
GROUP BY rideable_type, member_casual
ORDER BY member_casual, total_rides DESC;

--find out the top starting stations for casual riders
--finding: this identifies stations where casual riders are already active. these are strong candidates for station-based ads, qr-code promotions, tourist campagins, or in-app membership offers
SELECT 
  start_station_name,
  COUNT(*) AS total_casual_rides
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
WHERE
  member_casual = 'casual'
  AND start_station_name IS NOT NULL
GROUP BY start_station_name
ORDER BY total_casual_rides DESC
LIMIT 20;

--find out the top starting stations for members
--finding: this helps compare casual-heavy stations with member-heavy stations. member-heavy stations may reflect commuter or residential use.
SELECT 
  start_station_name,
  COUNT(*) AS total_member_rides
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
WHERE
  member_casual = 'member'
  AND start_station_name IS NOT NULL
GROUP BY start_station_name
ORDER BY total_member_rides DESC
LIMIT 20;

--find out which stations have the strongest casual rider concentration
--finding: a station with 10 casual rides and 0 member rides is technically 100% casual, but not meaningful. The HAVING total_rides >= 500 filter keeps the result focused on high-activity stations
SELECT 
  start_station_name,
  ROUND(AVG(start_lat), 6) AS avg_start_lat,
  ROUND(AVG(start_lng), 6) AS avg_start_lng,
  COUNT(*) AS total_rides,
  COUNTIF(member_casual = 'casual') AS total_casual_rides,
  COUNTIF(member_casual = 'member') AS total_member_rides,
  ROUND(100 * COUNTIF(member_casual = 'casual') / COUNT(*), 2) AS casual_percentage
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
WHERE
  start_station_name IS NOT NULL
GROUP BY start_station_name
HAVING total_rides >= 500
ORDER BY casual_percentage DESC;

--find out seasonality by rider type
--finding: casual and member rider usage is highest in Summer, when conversion campaigns should run.
SELECT 
  season,
  member_casual,
  COUNT(*) AS total_rides,
  ROUND(AVG(ride_length_minutes), 2) AS avg_ride_length
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
GROUP BY season, member_casual
ORDER BY
  CASE season
    WHEN 'Winter' THEN 1
    WHEN 'Spring' THEN 2
    WHEN 'Summer' THEN 3
    WHEN 'Fall' THEN 4
  END,
  member_casual;

--create member vs casual summary table
SELECT 
  member_casual,
  COUNT(*) AS total_rides,
  ROUND(AVG(ride_length_minutes), 2) AS avg_ride_length,
  APPROX_QUANTILES(ride_length_minutes, 100)[OFFSET(50)] AS median_ride_length,
  COUNT(DISTINCT ride_date) AS active_days,
  ROUND(COUNT(*) / COUNT(DISTINCT ride_date), 2) AS avg_rides_per_active_day
FROM `case-study-cylistic-sql.cyclistic_2025.tripdata2025Cleaned`
GROUP BY member_casual;

