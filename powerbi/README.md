The Power BI report "Bronings Executive Dashboard" was built in the Power BI service on the semantic model "Bronings Executive Model". It connects to Snowflake (BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS) through the read-only user PBI_USER and refreshes daily.

To add the .pbix file to this folder:
1. Open the report in app.powerbi.com.
2. Choose File > Download this file > "A copy of your report and data (.pbix)".
3. Save it here as bronings_dashboard.pbix.

Contents:
- 6 pages: Executive Summary, Emergency Department, Outpatient Waiting, Capacity, Finance, Workforce
- 12 required DAX measures plus supporting measures (see dax_measures.txt)
- RAG calculated columns on KPI_Scorecard
- 85% and 92% occupancy reference lines
- 12-week waiting-list forecast
- NHS colour theme (nhs_theme.json)
