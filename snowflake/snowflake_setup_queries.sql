/* =====================================================================
   BRONINGS UNIVERSITY HOSPITAL GROUP - SNOWFLAKE SETUP
   Database BRONINGS_ANALYTICS, schema HOSPITAL_OPERATIONS

   Run in a Snowsight SQL worksheet with "Run All".
   Every object name is fully qualified, so the script does not depend
   on the worksheet's current database or schema.
   Table and column names are double-quoted so that they keep the exact
   case of the CSV headers. Without quotes Snowflake would upper-case
   them and the Power BI DAX measures would no longer match.
   ===================================================================== */

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------
-- 1. Warehouse, database, schema, file format, stage
-- ---------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS BRONINGS_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
USE WAREHOUSE BRONINGS_WH;

CREATE DATABASE IF NOT EXISTS BRONINGS_ANALYTICS;
CREATE SCHEMA IF NOT EXISTS BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS;

CREATE OR REPLACE FILE FORMAT BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.CSV_HEADER
  TYPE = CSV
  PARSE_HEADER = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  EMPTY_FIELD_AS_NULL = TRUE
  NULL_IF = ('')
  TRIM_SPACE = TRUE
  DATE_FORMAT = 'YYYY-MM-DD'
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;      -- required with MATCH_BY_COLUMN_NAME

CREATE STAGE IF NOT EXISTS BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.RAW_STAGE
  FILE_FORMAT = BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.CSV_HEADER;

USE SCHEMA BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS;

-- ---------------------------------------------------------------------
-- 2. The five validated tables
-- NHS_Number is VARCHAR so that leading zeros are kept.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."OutpatientAppointments" (
  "Appointment_ID" VARCHAR(12), "NHS_Number" VARCHAR(10), "Patient_Surname" VARCHAR(50),
  "Patient_DOB" DATE, "Specialty_Code" VARCHAR(5), "Consultant_Code" VARCHAR(10),
  "Clinic_Code" VARCHAR(10), "Appointment_Date" DATE, "Week_Ending" DATE,
  "Appointment_Time" VARCHAR(5), "Attendance_Status" VARCHAR(5),
  "Waiting_Days" NUMBER(6,0),          -- validated: negatives removed, text values derived from RTT_Weeks x 7
  "Waiting_Days_Raw" VARCHAR(10), "Waiting_Days_Flag" VARCHAR(40), "RTT_Status" VARCHAR(10),
  "RTT_Weeks" NUMBER(6,1), "Referral_Source" VARCHAR(10), "Postcode" VARCHAR(10));

CREATE OR REPLACE TABLE BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."InpatientAdmissions" (
  "Episode_ID" VARCHAR(12), "NHS_Number" VARCHAR(10), "Patient_Surname" VARCHAR(50),
  "Patient_DOB" DATE, "Admission_Date" DATE, "Admission_Week_Ending" DATE,
  "Admission_Type" VARCHAR(10), "Ward_Code" VARCHAR(5), "Specialty_Code" VARCHAR(5),
  "Discharge_Date" DATE, "Discharge_Method" VARCHAR(12),
  "Length_of_Stay" NUMBER(5,0),        -- validated: recalculated from the admission and discharge dates
  "Length_of_Stay_Raw" VARCHAR(6), "Bed_Days" NUMBER(5,0),
  "Readmission_Flag" VARCHAR(1), "Readmission_Flag_Source" VARCHAR(12),
  "HRG_Code" VARCHAR(10), "Consultant_Code" VARCHAR(10), "ICD10_Code" VARCHAR(10), "OPCS4_Code" VARCHAR(10));

CREATE OR REPLACE TABLE BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."EDAttendances" (
  "Attendance_ID" VARCHAR(12), "NHS_Number" VARCHAR(10), "Patient_Surname" VARCHAR(50),
  "Patient_DOB" DATE, "Arrival_Date" DATE, "Arrival_Week_Ending" DATE, "Arrival_Time" VARCHAR(5),
  "Triage_Category" NUMBER(1,0), "Seen_by_Clinician_Time" VARCHAR(5), "Departure_Time" VARCHAR(5),
  "Departure_Code" VARCHAR(10), "Four_Hour_Breach" VARCHAR(1), "Total_ED_Time_Minutes" NUMBER(5,0),
  "Chief_Complaint" VARCHAR(60), "Specialty_Referred" VARCHAR(10));

CREATE OR REPLACE TABLE BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."TheatreUtilisation" (
  "Week_Ending" DATE, "Theatre_ID" VARCHAR(5), "Sessions_Available" NUMBER(4,0),
  "Sessions_Used" NUMBER(4,0), "Utilisation_Pct" NUMBER(6,1), "Cases_Planned" NUMBER(5,0),
  "Cases_Completed" NUMBER(5,0), "Cancellations_Trust" NUMBER(4,0), "Cancellations_Patient" NUMBER(4,0),
  "Overrun_Minutes" NUMBER(5,0), "Specialty_Code" VARCHAR(5), "Data_Flag" VARCHAR(30));

CREATE OR REPLACE TABLE BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."WorkforceStaffing" (
  "Shift_ID" VARCHAR(12), "Staff_ID" VARCHAR(10), "Staff_Grade" VARCHAR(10), "Ward_Code" VARCHAR(5),
  "Shift_Date" DATE, "Shift_Week_Ending" DATE, "Shift_Type" VARCHAR(6), "Hours_Rostered" NUMBER(5,2),
  "Hours_Worked" NUMBER(5,2), "Agency_Flag" VARCHAR(1), "Absence_Flag" VARCHAR(1),
  "Overtime_Hours" NUMBER(5,2), "Specialty_Code" VARCHAR(5));

-- ---------------------------------------------------------------------
-- 3. Load the files
-- First upload the five CSVs to RAW_STAGE (Snowsight: Add Data > Load files into a Stage).
-- ---------------------------------------------------------------------
LIST @BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.RAW_STAGE;     -- expect 5 files

COPY INTO BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."OutpatientAppointments"
  FROM @BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.RAW_STAGE FILES = ('OutpatientAppointments.csv')
  FILE_FORMAT = (FORMAT_NAME = 'BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.CSV_HEADER')
  MATCH_BY_COLUMN_NAME = CASE_SENSITIVE ON_ERROR = ABORT_STATEMENT;
COPY INTO BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."InpatientAdmissions"
  FROM @BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.RAW_STAGE FILES = ('InpatientAdmissions.csv')
  FILE_FORMAT = (FORMAT_NAME = 'BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.CSV_HEADER')
  MATCH_BY_COLUMN_NAME = CASE_SENSITIVE ON_ERROR = ABORT_STATEMENT;
COPY INTO BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."EDAttendances"
  FROM @BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.RAW_STAGE FILES = ('EDAttendances.csv')
  FILE_FORMAT = (FORMAT_NAME = 'BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.CSV_HEADER')
  MATCH_BY_COLUMN_NAME = CASE_SENSITIVE ON_ERROR = ABORT_STATEMENT;
COPY INTO BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."TheatreUtilisation"
  FROM @BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.RAW_STAGE FILES = ('TheatreUtilisation.csv')
  FILE_FORMAT = (FORMAT_NAME = 'BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.CSV_HEADER')
  MATCH_BY_COLUMN_NAME = CASE_SENSITIVE ON_ERROR = ABORT_STATEMENT;
COPY INTO BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."WorkforceStaffing"
  FROM @BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.RAW_STAGE FILES = ('WorkforceStaffing.csv')
  FILE_FORMAT = (FORMAT_NAME = 'BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS.CSV_HEADER')
  MATCH_BY_COLUMN_NAME = CASE_SENSITIVE ON_ERROR = ABORT_STATEMENT;

-- ---------------------------------------------------------------------
-- 4. Supporting objects for the dashboards
-- ---------------------------------------------------------------------
-- Date table for FY 2024/25. "Week_Ending" is the Sunday of each week.
CREATE OR REPLACE TABLE BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."DimDate" AS
SELECT d AS "Date",
       DATEADD(day, 7 - DAYOFWEEKISO(d), d) AS "Week_Ending",
       DATE_TRUNC('month', d) AS "Month_Start",
       TO_CHAR(d, 'MON YYYY') AS "Month_Name",
       '2024/25' AS "Fin_Year",
       CASE WHEN MONTH(d) BETWEEN 4 AND 6 THEN 'Q1' WHEN MONTH(d) BETWEEN 7 AND 9 THEN 'Q2'
            WHEN MONTH(d) BETWEEN 10 AND 12 THEN 'Q3' ELSE 'Q4' END AS "Fin_Quarter"
FROM (SELECT DATEADD(day, SEQ4(), '2024-04-01'::DATE) AS d FROM TABLE(GENERATOR(ROWCOUNT => 365)));

-- Finance: agency actual vs budget by month.
-- The budget is a PLACEHOLDER: the cost at the 8% Trust target (8% of classified shifts x GBP 385).
CREATE OR REPLACE VIEW BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."FinanceMonthly" AS
SELECT DATE_TRUNC('month', "Shift_Date") AS "Month_Start",
       COUNT_IF("Agency_Flag" = 'Y') AS "Agency_Shifts",
       COUNT(*) AS "Classified_Shifts",
       COUNT_IF("Agency_Flag" = 'Y') * 385 AS "Agency_Actual_GBP",
       ROUND(COUNT(*) * 0.08 * 385, 2) AS "Agency_Budget_GBP"
FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."WorkforceStaffing"
WHERE "Agency_Flag" IN ('Y','N')
GROUP BY 1;

-- KPI targets taken from the Phase 5 18-KPI Framework
CREATE OR REPLACE TABLE BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."KPI_Scorecard" (
  "KPI_Order" NUMBER(2,0), "KPI_Code" VARCHAR(10), "KPI_Name" VARCHAR(60), "Target" NUMBER(6,2),
  "Amber_Threshold" NUMBER(6,2), "Higher_Is_Better" BOOLEAN, "Unit" VARCHAR(10), "Target_Text" VARCHAR(30));
INSERT INTO BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."KPI_Scorecard" VALUES
 (1,'4HT','ED 4-hour compliance',90,78,TRUE,'%','>= 90%'),
 (2,'LWBS','ED left without being seen',5,7,FALSE,'%','< 5%'),
 (3,'DNA','Outpatient DNA rate',8,10,FALSE,'%','< 8%'),
 (4,'RTT','RTT 18-week compliance (open)',88,65,TRUE,'%','>= 88%'),
 (5,'THEATRE','Theatre utilisation (sessions)',85,75,TRUE,'%','>= 85%'),
 (6,'ALOS','Average length of stay',4.5,5.0,FALSE,'days','< 4.5 days'),
 (7,'READM','30-day readmission rate',10,12,FALSE,'%','< 10%'),
 (8,'HRG','HRG coding completeness',98,95,TRUE,'%','>= 98%'),
 (9,'AGENCY','Agency share of shifts',8,10,FALSE,'%','< 8%');

-- KPI actuals: one row per KPI, used for the Tableau scorecard
CREATE OR REPLACE VIEW BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."KPI_Actuals" AS
WITH a AS (
  SELECT '4HT' AS code, ROUND(100 * COUNT_IF("Total_ED_Time_Minutes" <= 240) / COUNT(*), 2) AS actual FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."EDAttendances"
  UNION ALL SELECT 'LWBS', ROUND(100 * COUNT_IF("Departure_Code" = 'LWBS') / COUNT(*), 2) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."EDAttendances"
  UNION ALL SELECT 'DNA', ROUND(100 * COUNT_IF("Attendance_Status" = 'DNA') / NULLIF(COUNT_IF("Attendance_Status" IN ('ATT','DNA')), 0), 2) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."OutpatientAppointments"
  UNION ALL SELECT 'RTT', ROUND(100 * COUNT_IF("RTT_Status" = 'OPEN' AND COALESCE("RTT_Weeks", 0) <= 18) / NULLIF(COUNT_IF("RTT_Status" = 'OPEN'), 0), 2) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."OutpatientAppointments"
  UNION ALL SELECT 'THEATRE', ROUND(100 * SUM("Sessions_Used") / SUM("Sessions_Available"), 2) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."TheatreUtilisation"
  UNION ALL SELECT 'ALOS', ROUND(AVG(CASE WHEN "Length_of_Stay" >= 0 THEN "Length_of_Stay" END), 2) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."InpatientAdmissions"
  UNION ALL SELECT 'READM', ROUND(100 * COUNT_IF("Readmission_Flag" = 'Y') / NULLIF(COUNT_IF("Readmission_Flag" IN ('Y','N')), 0), 2) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."InpatientAdmissions"
  UNION ALL SELECT 'HRG', ROUND(100 * COUNT_IF("HRG_Code" IS NOT NULL) / COUNT(*), 2) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."InpatientAdmissions"
  UNION ALL SELECT 'AGENCY', ROUND(100 * COUNT_IF("Agency_Flag" = 'Y') / NULLIF(COUNT_IF("Agency_Flag" IN ('Y','N')), 0), 2) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."WorkforceStaffing")
SELECT k.*, a.actual AS "Actual" FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."KPI_Scorecard" k JOIN a ON a.code = k."KPI_Code";

-- Weekly midnight bed census (Sunday): patients in hospital / 380 beds
CREATE OR REPLACE VIEW BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."OccupancyWeekly" AS
SELECT w."Week_Ending", COUNT(i."Episode_ID") AS "Patients_In_Bed", ROUND(100 * COUNT(i."Episode_ID") / 380, 2) AS "Occupancy_Pct"
FROM (SELECT DISTINCT "Week_Ending" FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."DimDate"
      WHERE "Week_Ending" BETWEEN '2024-10-06' AND '2025-03-30') w
LEFT JOIN BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."InpatientAdmissions" i
  ON i."Admission_Date" <= w."Week_Ending" AND (i."Discharge_Date" IS NULL OR i."Discharge_Date" > w."Week_Ending")
GROUP BY w."Week_Ending";

-- ---------------------------------------------------------------------
-- 5. Read-only role and user for Power BI
-- Set a strong password before running. Never commit a real password.
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS PBI_READER;
GRANT USAGE ON WAREHOUSE BRONINGS_WH TO ROLE PBI_READER;
GRANT USAGE ON DATABASE BRONINGS_ANALYTICS TO ROLE PBI_READER;
GRANT USAGE ON SCHEMA BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS TO ROLE PBI_READER;
GRANT SELECT ON ALL TABLES IN SCHEMA BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS TO ROLE PBI_READER;
GRANT SELECT ON ALL VIEWS IN SCHEMA BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS TO ROLE PBI_READER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS TO ROLE PBI_READER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS TO ROLE PBI_READER;

CREATE USER IF NOT EXISTS PBI_USER
  LOGIN_NAME = 'PBI_USER'
  PASSWORD = '<set-a-strong-password>'
  DEFAULT_ROLE = PBI_READER
  DEFAULT_WAREHOUSE = BRONINGS_WH
  DEFAULT_NAMESPACE = BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS
  MUST_CHANGE_PASSWORD = FALSE;
GRANT ROLE PBI_READER TO USER PBI_USER;

-- ---------------------------------------------------------------------
-- 6. Checks (expected values in the comments)
-- ---------------------------------------------------------------------
SELECT 'OutpatientAppointments' AS t, COUNT(*) AS n FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."OutpatientAppointments"   -- 580
UNION ALL SELECT 'InpatientAdmissions', COUNT(*) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."InpatientAdmissions"          -- 1200
UNION ALL SELECT 'EDAttendances', COUNT(*) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."EDAttendances"                      -- 960
UNION ALL SELECT 'TheatreUtilisation', COUNT(*) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."TheatreUtilisation"            -- 208
UNION ALL SELECT 'WorkforceStaffing', COUNT(*) FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."WorkforceStaffing";            -- 1536

SELECT "KPI_Code", "Actual" FROM BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS."KPI_Actuals" ORDER BY "KPI_Order";
-- 4HT 80.10 | LWBS 2.40 | DNA 14.07 | RTT 41.98 | THEATRE 70.75 | ALOS 3.88 | READM 9.50 | HRG 97.67 | AGENCY 16.57
