Select job_title_short, avg(salary_year_avg), median(salary_year_avg),MAX(salary_year_avg)
from job_postings_fact
group by 
job_title_short
having 
median(salary_year_avg)>100_000
Order by
avg(salary_year_avg) DESC 