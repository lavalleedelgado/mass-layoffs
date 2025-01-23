# Mass layoffs and college enrollment in Maine
Patrick Lavallee Delgado \
University of Pennsylvania \
November 2024

## Abstract

Mass layoffs are a strong signal against pursuing a career in the affected industry. Students at the postsecondary transition may make a different choice than they otherwise would with additional information about the regional labor market. Whether a mass layoff is a strong enough nudge to induce a shift towards postsecondary education has equity implications for regional economic development and college access. I attempt to model the accumulation of mass layoff signals that students perceive at their respective schools, proportional to the relative severity and proximity of each event. This approach accounts for how a relatively rare but significant event can have variable but non-negligible impacts on students' decision-making across the state.

I offer this repository to replicate these findings.

## Data

- Worker Adjustment and Retraining Notification (WARN) Act. Under federal and Maine law, certain employers are required to give their employees 90 days' notice ahead of a plan closure or mass layoff. Maine DOL maintains a database of WARN notices [here](https://joblink.maine.gov/search/warn_lookups/new). I look for news articles to fill in missing location information and also associate each site with a [NAICS](https://www.naics.com/search/) code.

- National Student Clearinghouse StudentTracker for High Schools. These data count the number of high school students in each graduating cohort who enroll in college by institution type. Maine DOE purchases these reports from the NCS and publishes them online [here](https://www.maine.gov/doe/data-reporting/reporting/warehouse/outcomes).

- Common Core of Data (CCD). These data are a census of public schools in the country. They describe school type, location, urbanicity, enrollment by grade, Title I status, and free and reduced price lunch receipt. Urban Institute harmonizes these data across years [here](https://educationdata.urban.org/documentation/).

- EDFacts. These data report proficiency and graduation rates for public schools in the country. Importantly, EDFacts does not disaggregate math and reading proficiency rates for high school grades. Urban Institute harmonizes these data across years [here](https://educationdata.urban.org/documentation/).

- NCES-CEEB crosswalk. This file maps unique identifies for high schools between the National Center for Education Statistics (NCES) and College Entrance Examination Board (CEEB) systems. CU Boulder maintains this dataset [here](https://github.com/cu-boulder/ceeb_nces_crosswalk). However, it does not handle changes over time, such as when schools open, merge, or close. I create a supplement to this crosswalk specifically for public high schools in Maine.

- American Community Survey (ACS) five-year estimates. These data describe the educational attainment, employment characteristics, and median household income of residents in the census tract of each high school. This is a proxy for a description of the catchment area of each high school. In rural areas, the census tract usually contains the catchment area. Census has a public API [here](https://www.census.gov/programs-surveys/acs/data.html).

- TIGER/Line shapefiles. This file draws the 2010 census tracts for the state of Maine, and facilitates a spatial join of high schools and mass layoff sites onto census data. Census has this file available [here](https://www2.census.gov/geo/tiger/TIGER2019/TRACT/tl_2019_23_tract.zip).

## Programs

- `01-get-nsc.sh` downloads pdfs of NSC data and scrapes the tables into a dataset.
- `01-get-urban.sh` downloads CCD and EDFacts data from the Urban Institute API.
- `01-get-acs.sh` downloads ACS data.
- `01-get-shp.sh` downloads census tract shapefiles.
- `02a-locate-sites.py` identifies the latitude and longitude of each mass layoff site, calculates the straight line distance of each site to each school in the CCD, and joins each site-school pair with the census tract of the school.
- `02b-calculate-weights.r` calculate the total workforce within commuting distance of each school.
- `03-build-dataset.do` collects the data into an analytic file.
- `04-run-analysis.do` estimates the models presented in the paper.
- `05-make-maps.r` draws maps presented in the paper.
