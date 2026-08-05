select 
job_id,
job_title_short,
company_id,
From job_postings_fact
Limit 10;

Select company_id,name from company_dim;

Select * from company_dim 
where name in ('Google','Facebook','Amazon','Microsoft','Apple')
limit 10;


select * from skills_job_dim
limit 10;
Select * from Information_schema.columns
Where table_catalog = 'data_jobs';


Select table_name,column_name,data_type from Information_schema.table_constraints
Where table_catalog ='data_jobs';


Select * from Information_schema.table_constraints
Where table_catalog ='data_jobs';


PRAGMA Show_tables;
PRAGMA Show_tables_expanded;

DESCRIBE job_postings_fact;