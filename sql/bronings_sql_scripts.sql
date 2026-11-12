/* =====================================================================================
   BRONINGS UNIVERSITY HOSPITAL GROUP - SQL INVESTIGATION (PHASE 4)
   Server   : BRONINGS-SQL01\SQLEXPRESS     Database : BroningsAnalytics
   Author   : Advanced Healthcare Data Analyst
   Syntax   : T-SQL (SQL Server 2017+; STRING_AGG is needed for Query 6)

   Conventions used throughout, so every query treats the data the same way:
   - Columns are assumed to be loaded as text (NVARCHAR) with the CSV column names.
     Blank fields may arrive as '' or NULL, so each query wraps them in NULLIF(..., '').
   - Numbers are read with TRY_CAST. Text in a numeric field (e.g. 'ATT' in Waiting_Days)
     becomes NULL instead of stopping the query.
   - Dates are UK format DD/MM/YYYY, read with TRY_CONVERT(date, col, 103). The 3 inpatient
     discharge dates typed as 'October 9 2024' fall back to TRY_CONVERT(date, col).
   - 18 weeks = 126 days. Negative waits are invalid and excluded (Module A, DQ-018).
   - SELECT DISTINCT * removes the 2 exact duplicate inpatient episodes (Module A, DQ-016).
   ===================================================================================== */

USE BroningsAnalytics;
GO

/* -------------------------------------------------------------------------------------
   QUERY 1 - RTT BREACH BY SPECIALTY (open pathways only)
   For each specialty: open pathways, number waiting more than 18 weeks (126 days), and
   compliance % = open pathways within 18 weeks / all open pathways.
   NHS England standard: 92%. Worst specialty first.
   ------------------------------------------------------------------------------------- */
WITH OpenPathways AS (
    SELECT  Specialty_Code,
            TRY_CAST(Waiting_Days AS INT) AS WaitDays
    FROM    dbo.OutpatientAppointments
    WHERE   RTT_Status = 'OPEN'
      AND   TRY_CAST(Waiting_Days AS INT) >= 0          -- drop invalid/negative waits
)
SELECT  Specialty_Code,
        COUNT(*)                                              AS Total_Open_Pathways,
        SUM(CASE WHEN WaitDays > 126 THEN 1 ELSE 0 END)       AS Patients_Breaching_18wks,
        CAST(100.0 * SUM(CASE WHEN WaitDays <= 126 THEN 1 ELSE 0 END)
             / COUNT(*) AS DECIMAL(5,2))                      AS Compliance_Pct,
        CASE WHEN 100.0 * SUM(CASE WHEN WaitDays <= 126 THEN 1 ELSE 0 END) / COUNT(*) >= 92
             THEN 'Meets 92%' ELSE 'BREACH' END               AS Status_vs_92pct
FROM    OpenPathways
GROUP BY Specialty_Code
ORDER BY Compliance_Pct ASC;
GO

/* -------------------------------------------------------------------------------------
   QUERY 2 - CONSULTANT TRUST-INITIATED CANCELLATION RATE
   CAN = cancelled by the hospital (Trust). Rate = CAN / all appointments for that
   consultant in that specialty. RANK() orders consultants within each specialty, and a
   second RANK() orders them across the Trust.
   ------------------------------------------------------------------------------------- */
WITH ConsultantActivity AS (
    SELECT  Specialty_Code,
            Consultant_Code,
            COUNT(*)                                                AS Total_Appointments,
            SUM(CASE WHEN Attendance_Status = 'CAN' THEN 1 ELSE 0 END) AS Trust_Cancellations
    FROM    dbo.OutpatientAppointments
    WHERE   NULLIF(Consultant_Code, '') IS NOT NULL             -- 5 rows have no consultant
    GROUP BY Specialty_Code, Consultant_Code
)
SELECT  Specialty_Code,
        Consultant_Code,
        Total_Appointments,
        Trust_Cancellations,
        CAST(100.0 * Trust_Cancellations / Total_Appointments AS DECIMAL(5,2)) AS Cancellation_Rate_Pct,
        RANK() OVER (PARTITION BY Specialty_Code
                     ORDER BY 1.0 * Trust_Cancellations / Total_Appointments DESC) AS Rank_In_Specialty,
        RANK() OVER (ORDER BY 1.0 * Trust_Cancellations / Total_Appointments DESC) AS Rank_Trust_Wide
FROM    ConsultantActivity
ORDER BY Cancellation_Rate_Pct DESC, Total_Appointments DESC;
GO

/* -------------------------------------------------------------------------------------
   QUERY 3 - CLINIC DNA RATE
   Only the four valid statuses (ATT, DNA, CAN, REF) are counted, which excludes
   'attended' and 'N/A'. DNA rate = DNA / total valid appointments.
   ------------------------------------------------------------------------------------- */
SELECT  Clinic_Code,
        COUNT(*)                                                  AS Total_Appointments,
        SUM(CASE WHEN Attendance_Status = 'DNA' THEN 1 ELSE 0 END)  AS DNA_Count,
        CAST(100.0 * SUM(CASE WHEN Attendance_Status = 'DNA' THEN 1 ELSE 0 END)
             / COUNT(*) AS DECIMAL(5,2))                          AS DNA_Rate_Pct
FROM    dbo.OutpatientAppointments
WHERE   Attendance_Status COLLATE Latin1_General_CS_AS IN ('ATT','DNA','CAN','REF')  -- case-sensitive
GROUP BY Clinic_Code
ORDER BY DNA_Rate_Pct DESC;
GO

/* -------------------------------------------------------------------------------------
   QUERY 4 - WARD OCCUPANCY BY WEEK
   Census at the end of each Sunday from 06/10/2024 to 23/03/2025. A patient counts as
   present if admitted on or before the census date and either not yet discharged (blank)
   or discharged after it. Then: how many weeks did each ward have more than 10 patients?
   ------------------------------------------------------------------------------------- */
WITH Weeks AS (                                   -- one row per Sunday census date
    SELECT CAST('2024-10-06' AS DATE) AS Census_Date
    UNION ALL
    SELECT DATEADD(DAY, 7, Census_Date) FROM Weeks WHERE Census_Date < '2025-03-23'
),
Spells AS (                                       -- clean dates; exact duplicates removed
    SELECT DISTINCT
           Episode_ID, Ward_Code,
           TRY_CONVERT(DATE, Admission_Date, 103) AS Adm_Date,
           COALESCE(TRY_CONVERT(DATE, NULLIF(Discharge_Date,''), 103),
                    TRY_CONVERT(DATE, NULLIF(Discharge_Date,'')))  AS Dis_Date
    FROM   dbo.InpatientAdmissions
),
Occupancy AS (
    SELECT w.Census_Date, s.Ward_Code, COUNT(*) AS Concurrent_Patients
    FROM   Weeks w
    JOIN   Spells s
      ON   s.Adm_Date <= w.Census_Date
     AND  (s.Dis_Date IS NULL OR s.Dis_Date > w.Census_Date)
    GROUP BY w.Census_Date, s.Ward_Code
)
SELECT  Ward_Code,
        SUM(CASE WHEN Concurrent_Patients > 10 THEN 1 ELSE 0 END) AS Weeks_Over_10,
        (SELECT COUNT(*) FROM Weeks)                               AS Weeks_Measured,
        MAX(Concurrent_Patients)                                   AS Peak_Patients,
        CAST(AVG(1.0 * Concurrent_Patients) AS DECIMAL(5,1))       AS Avg_Patients
FROM    Occupancy
GROUP BY Ward_Code
ORDER BY Weeks_Over_10 DESC, Peak_Patients DESC
OPTION (MAXRECURSION 0);
GO

/* -------------------------------------------------------------------------------------
   QUERY 5 - DEPARTMENTAL WAITING TIMES (open RTT pathways)
   SQL Server has no MEDIAN(). PERCENTILE_CONT(0.5) is a window function, so it is worked
   out per row in a CTE and then collapsed with GROUP BY.
   ------------------------------------------------------------------------------------- */
WITH OpenWaits AS (
    SELECT  Specialty_Code,
            TRY_CAST(Waiting_Days AS INT) AS WaitDays,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TRY_CAST(Waiting_Days AS INT))
                OVER (PARTITION BY Specialty_Code) AS Median_Days
    FROM    dbo.OutpatientAppointments
    WHERE   RTT_Status = 'OPEN'
      AND   TRY_CAST(Waiting_Days AS INT) >= 0
)
SELECT  Specialty_Code,
        COUNT(*)                                     AS Open_Pathways,
        CAST(AVG(1.0 * WaitDays) AS DECIMAL(6,2))     AS Avg_Waiting_Days,
        MAX(Median_Days)                             AS Median_Waiting_Days,
        MAX(WaitDays)                                AS Max_Waiting_Days
FROM    OpenWaits
GROUP BY Specialty_Code
ORDER BY Avg_Waiting_Days DESC;
GO

/* -------------------------------------------------------------------------------------
   QUERY 6 - DUPLICATE PATIENT RECORDS (NHS Number appearing more than once)
   Patients with several appointments are normal. The real problem is one NHS Number
   attached to different surnames or dates of birth, which points to a wrong or reused
   number.
   ------------------------------------------------------------------------------------- */
WITH Repeats AS (
    SELECT  NHS_Number,
            COUNT(*)                        AS Appointment_Count,
            COUNT(DISTINCT Patient_Surname) AS Distinct_Surnames,
            COUNT(DISTINCT Patient_DOB)     AS Distinct_DOBs
    FROM    dbo.OutpatientAppointments
    WHERE   NULLIF(NHS_Number, '') IS NOT NULL
    GROUP BY NHS_Number
    HAVING  COUNT(*) > 1
),
Names AS (                                         -- list of surnames used per NHS Number
    SELECT  NHS_Number, STRING_AGG(Patient_Surname, ' / ') AS Surnames
    FROM   (SELECT DISTINCT NHS_Number, Patient_Surname FROM dbo.OutpatientAppointments) d
    GROUP BY NHS_Number
)
SELECT  r.NHS_Number,
        n.Surnames,
        r.Appointment_Count,
        CASE WHEN r.Distinct_Surnames = 1 AND r.Distinct_DOBs = 1
             THEN 'Consistent'
             ELSE 'INCONSISTENT - ' + CAST(r.Distinct_Surnames AS VARCHAR(3)) + ' surname(s), '
                                    + CAST(r.Distinct_DOBs AS VARCHAR(3)) + ' DOB(s)' END AS Demographic_Check
FROM    Repeats r
JOIN    Names   n ON n.NHS_Number = r.NHS_Number
ORDER BY CASE WHEN r.Distinct_Surnames = 1 AND r.Distinct_DOBs = 1 THEN 1 ELSE 0 END,  -- problems first
         r.Appointment_Count DESC;
GO

/* -------------------------------------------------------------------------------------
   QUERY 7 - LOST REFERRALS
   Open RTT pathways whose NHS Number never appears in InpatientAdmissions or
   EDAttendances. "Same period" is the whole extract window (Oct 2024 - Mar 2025).
   ------------------------------------------------------------------------------------- */
SELECT  o.Specialty_Code,
        COUNT(*)                     AS Open_Pathways_No_Onward_Activity,
        COUNT(DISTINCT o.NHS_Number) AS Patients
FROM    dbo.OutpatientAppointments o
WHERE   o.RTT_Status = 'OPEN'
  AND   NULLIF(o.NHS_Number, '') IS NOT NULL
  AND   NOT EXISTS (SELECT 1 FROM dbo.InpatientAdmissions i WHERE i.NHS_Number = o.NHS_Number)
  AND   NOT EXISTS (SELECT 1 FROM dbo.EDAttendances      e WHERE e.NHS_Number = o.NHS_Number)
GROUP BY o.Specialty_Code
ORDER BY Open_Pathways_No_Onward_Activity DESC;
GO

/* -------------------------------------------------------------------------------------
   QUERY 8 - REVENUE LEAKAGE (blank HRG_Code)
   An episode without an HRG code is not paid. GBP 1,850 per episode (Company Brief).
   ------------------------------------------------------------------------------------- */
DECLARE @TariffPerEpisode MONEY = 1850;

WITH Episodes AS (SELECT DISTINCT * FROM dbo.InpatientAdmissions)   -- remove exact duplicates
SELECT  Specialty_Code,
        COUNT(*)                                                       AS Total_Episodes,
        SUM(CASE WHEN NULLIF(HRG_Code,'') IS NULL THEN 1 ELSE 0 END)    AS Blank_HRG,
        CAST(100.0 * SUM(CASE WHEN NULLIF(HRG_Code,'') IS NULL THEN 1 ELSE 0 END)
             / COUNT(*) AS DECIMAL(5,2))                               AS Blank_Pct,
        SUM(CASE WHEN NULLIF(HRG_Code,'') IS NULL THEN 1 ELSE 0 END)
             * @TariffPerEpisode                                       AS Revenue_At_Risk_GBP
FROM    Episodes
GROUP BY ROLLUP (Specialty_Code)               -- final NULL row = Trust total
ORDER BY GROUPING(Specialty_Code), Blank_HRG DESC;
GO

/* -------------------------------------------------------------------------------------
   QUERY 9 - SERVICES BEATING THE 8% DNA TARGET
   DNA rate = DNA / (ATT + DNA). Cancellations and refusals are excluded because the
   patient was never expected to attend. Returns only specialties below 8%.
   ------------------------------------------------------------------------------------- */
WITH SpecialtyDNA AS (
    SELECT  Specialty_Code,
            SUM(CASE WHEN Attendance_Status = 'ATT' THEN 1 ELSE 0 END) AS Attended,
            SUM(CASE WHEN Attendance_Status = 'DNA' THEN 1 ELSE 0 END) AS DNA
    FROM    dbo.OutpatientAppointments
    WHERE   Attendance_Status COLLATE Latin1_General_CS_AS IN ('ATT','DNA')
    GROUP BY Specialty_Code
)
SELECT  Specialty_Code, Attended, DNA,
        CAST(100.0 * DNA / (Attended + DNA) AS DECIMAL(5,2)) AS DNA_Rate_Pct
FROM    SpecialtyDNA
WHERE   100.0 * DNA / (Attended + DNA) < 8.0
ORDER BY DNA_Rate_Pct ASC;
GO

/* -------------------------------------------------------------------------------------
   QUERY 10 - READMISSION PATTERN (Readmission_Flag = 'Y')
   The CTE standardises Admission_Type ('Elective' -> ELEC, 'emergency' -> EMER) before
   counting, then counts by type, by specialty and by both.
   ------------------------------------------------------------------------------------- */
WITH Readmissions AS (
    SELECT  CASE UPPER(Admission_Type)
                 WHEN 'ELECTIVE'  THEN 'ELEC'
                 WHEN 'EMERGENCY' THEN 'EMER'
                 ELSE UPPER(Admission_Type) END AS Adm_Type,
            Specialty_Code
    FROM   (SELECT DISTINCT * FROM dbo.InpatientAdmissions) i
    WHERE   Readmission_Flag = 'Y'
)
SELECT  Adm_Type, Specialty_Code, COUNT(*) AS Readmissions
FROM    Readmissions
GROUP BY GROUPING SETS ((Adm_Type), (Specialty_Code), (Adm_Type, Specialty_Code))
ORDER BY CASE WHEN Adm_Type IS NOT NULL AND Specialty_Code IS NULL THEN 1
              WHEN Adm_Type IS NULL THEN 2 ELSE 3 END,
         Readmissions DESC;
GO

/* -------------------------------------------------------------------------------------
   QUERY 11 - AGENCY SPEND BY WARD
   Confirmed agency shifts only: Agency_Flag = 'Y'. Blank flags are excluded, and so are
   ST-99 training-environment test records. Rows with a blank Staff_ID are kept: they are
   not test records, and NOT LIKE on a NULL would silently drop them. GBP 385 per shift.
   ------------------------------------------------------------------------------------- */
DECLARE @CostPerAgencyShift MONEY = 385;

SELECT  Ward_Code,
        COUNT(*)                        AS Confirmed_Agency_Shifts,
        COUNT(*) * @CostPerAgencyShift  AS Estimated_Cost_GBP
FROM    dbo.WorkforceStaffing
WHERE   Agency_Flag = 'Y'
  AND  (NULLIF(Staff_ID,'') IS NULL OR Staff_ID NOT LIKE 'ST-99%')
GROUP BY ROLLUP (Ward_Code)
ORDER BY GROUPING(Ward_Code), Confirmed_Agency_Shifts DESC;
GO

/* -------------------------------------------------------------------------------------
   QUERY 12 - THEATRE CANCELLATION PATTERN
   12a: day-of-week check on Week_Ending. The table holds one row per theatre per week, so
        this only shows which day each week is stamped with.
   12b: cancellations by specialty, normalised per theatre-week.
   12c: the week x specialty combinations with the most cancellations.
   Blank cancellation counts are treated as 0 (30 Trust and 23 patient blanks), so totals
   are a minimum.
   ------------------------------------------------------------------------------------- */
-- 12a
SELECT  DATENAME(WEEKDAY, TRY_CONVERT(DATE, Week_Ending, 103)) AS Week_Ending_Day,
        COUNT(*)                                               AS Theatre_Weeks,
        SUM(ISNULL(TRY_CAST(Cancellations_Trust AS INT),0)
          + ISNULL(TRY_CAST(Cancellations_Patient AS INT),0))  AS Cancellations
FROM    dbo.TheatreUtilisation
GROUP BY DATENAME(WEEKDAY, TRY_CONVERT(DATE, Week_Ending, 103));

-- 12b
SELECT  Specialty_Code,
        COUNT(*)                                               AS Theatre_Weeks,
        SUM(ISNULL(TRY_CAST(Cancellations_Trust AS INT),0))    AS Trust_Cancellations,
        SUM(ISNULL(TRY_CAST(Cancellations_Patient AS INT),0))  AS Patient_Cancellations,
        SUM(ISNULL(TRY_CAST(Cancellations_Trust AS INT),0)
          + ISNULL(TRY_CAST(Cancellations_Patient AS INT),0))  AS Total_Cancellations,
        CAST(1.0 * SUM(ISNULL(TRY_CAST(Cancellations_Trust AS INT),0)
                     + ISNULL(TRY_CAST(Cancellations_Patient AS INT),0))
             / COUNT(*) AS DECIMAL(5,2))                       AS Cancellations_Per_Theatre_Week
FROM    dbo.TheatreUtilisation
GROUP BY Specialty_Code
ORDER BY Cancellations_Per_Theatre_Week DESC;

-- 12c
SELECT TOP (10)
        Week_Ending,
        Specialty_Code,
        COUNT(*)                                               AS Theatres,
        SUM(ISNULL(TRY_CAST(Cancellations_Trust AS INT),0)
          + ISNULL(TRY_CAST(Cancellations_Patient AS INT),0))  AS Total_Cancellations
FROM    dbo.TheatreUtilisation
GROUP BY Week_Ending, Specialty_Code
ORDER BY Total_Cancellations DESC, TRY_CONVERT(DATE, Week_Ending, 103);
GO
