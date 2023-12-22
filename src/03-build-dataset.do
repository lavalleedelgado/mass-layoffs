version 18
clear all
set type double
set linesize 120

********************************************************************************
* Set up.
********************************************************************************

* Identify inputs and outputs.
local PWD "`c(pwd)'"
local LOG "`PWD'/src/03-build-dataset.log"
local ADO "`PWD'/src/ado"
local DTA "`PWD'/in"
local XWK "`DTA'/nces-ceeb-xwalk.csv"
local FIX "`DTA'/nces-ceeb-update.csv"
local NCS "`DTA'/ncs.csv"
local CCD "`DTA'/ccd.csv"
local EDF "`DTA'/edfacts.csv"
local WRN "`DTA'/warn.xlsx"
local LOC "`DTA'/loc.csv"
local ACS "`DTA'/acs.csv"
local VAR "`DTA'/varlist.xlsx"
local OUT "`PWD'/out/analysis.dta"

* Add project commands to the path.
adopath ++ "`ADO'"

* Start the log.
capture log close
log using "`LOG'", replace

********************************************************************************
*
* Project:  Mass layoffs
* Purpose:  Build analytic file
* Author:   Patrick Lavallee Delgado
* Created:  16 December 2023
*
* Notes:    Systematically missing outcomes for some closed or merged schools.
*
* To do:    Update tracts for 2020 decennial census to incorporate SY 20-21.
*
********************************************************************************


********************************************************************************
* Update CEEB-NCES id crosswalk.
********************************************************************************

* Set school year range.
local ymin 1011
local ymax 2021

* Read updates.
import delimited "`FIX'", clear
tostring ncessch, format(%12.0f) replace
isid ncessch
replace cohort_min = `ymin' if mi(cohort_min)
replace cohort_max = `ymax' if mi(cohort_max)
tempfile fix
save `fix'

* Read crosswalk.
import delimited "`XWK'", clear
rename hs_ceeb ceeb
rename hs_nces ncessch_old
rename hs_name school_name
keep if hs_state == "ME"
isid ceeb
isid ncessch_old

* Apply updates.
merge 1:m ceeb using `fix', update replace
replace ncessch = ncessch_old if _merge == 1
expand (`ymax' - `ymin') / 101 + 1
bysort ceeb ncessch: gen cohort = `ymin' + (_n - 1) * 101
assert mi(cohort_min) == mi(cohort_max)
keep if inrange(cohort, cohort_min, cohort_max)
isid cohort ceeb
isid cohort ncessch

* Set aside for merge.
keep cohort ceeb ncessch school_name
tempfile xwk
save `xwk'

********************************************************************************
* Load cohort enrollment data.
********************************************************************************

tempvar x

* Read NSC data.
import delimited "`NCS'", clear
describe
gen lag = (sy - cohort) / 101
drop sy
isid ceeb cohort lag, missok

* Drop overall state counts.
drop if mi(ceeb)
isid ceeb cohort lag

* Fix bug in NSC processing that creates more than two lags.
list ceeb school_name cohort lag if lag > 2, noobs
drop if lag > 2
assert inlist(lag, 0, 1, 2)

* Transform to school-cohort level.
recode lag (0 = 6) (1 = 12) (2 = 24)
reshape wide n_*, i(ceeb cohort) j(lag)

* Merge onto NCES ids.
merge 1:1 ceeb cohort using `xwk'
tabulate cohort _merge

* Drop schools not in CCD universe.
* These are private schools in the crosswalk.
gen `x' = !ustrregexm(ncessch, "^23[0-9]{10}$") & !mi(ncessch)
preserve
  keep if `x'
  bysort ncessch (cohort): keep if _n == _N
  isid ncessch
  count
  list ncessch ceeb school_name, noobs
restore
drop if `x'
drop `x'

* Drop all other unresolved schools.
* These are private and alternative schools not in the crosswalk.
assert mi(ncessch) == (_merge == 1)
tablist ceeb school_name if mi(ncessch)
drop if mi(ncessch)

* Mark school-cohorts with no outcomes.
* Compare against CCD to check whether zero or structurally missing.
gen check = _merge == 2
drop _merge

********************************************************************************
* Load cohort characteristics.
********************************************************************************

* Numericize NCES id.
destring ncessch, replace
format ncessch %12.0f

* Load EDFacts data.
* Set missing proficiency rates in SY 19-20 to values from SY 18-19.
preserve
  import delimited "`EDF'", clear
  rename *_test_pct_prof_midpt pct_prof_*
  describe
  isid year ncessch
  assert year != 2019
  expand 2 if year == 2018, gen(dup)
  replace year = 2019 if dup
  keep year ncessch pct_prof_*
  tempfile edf
  save `edf'
restore

* Merge onto CCD and EDFacts data.
preserve
  import delimited "`CCD'", clear
  rename (sex_* race_*) cohort_=
  describe
  isid year ncessch
  merge 1:1 year ncessch using `edf', assert(1 3) nogen
  gen cohort = mod(year, 100) * 100 + mod(year, 100) + 1
  tempfile ccd
  save `ccd'
restore
merge 1:1 ncessch cohort using `ccd', update replace

* Drop school-cohorts in NSC outside range of CCD.
* These are school years before opening or after closure.
bysort ceeb: egen cohort_min = min(cond(_merge > 1, cohort, .))
bysort ceeb: egen cohort_max = max(cond(_merge > 1, cohort, .))
gen `x' = !inrange(cohort, cohort_min, cohort_max)
assert check == 1 & _merge == 1 if `x'
drop if `x'
drop `x'

* Drop remaining unmatched school-cohorts in NSC.
* These schools closed before the observation window.
bysort ceeb: egen `x' = min(_merge == 1)
list ncessch school_name cohort check if `x', ab(32) noobs
assert check == 1 if `x'
drop if `x'
drop `x'
assert _merge > 1

* Drop matched school-cohorts that are not regular schools.
* These are career and technical schools and alternative schools.
tabulate school_type _merge
assert check == 1 if _merge > 2 & school_type != 1
drop if school_type != 1

* Drop matched school-cohorts with no outcomes and marked as closed.
* Note this assumes future schools with outcomes were already open.
tabulate school_status _merge
gen `x' = school_status == 2
list ncessch school_name cohort school_status check if `x' & _merge > 2, ab(32) noobs
assert check == 1 if `x' & _merge > 2
drop if `x'
drop `x'

* Drop matched school-cohorts with no outcomes and that are not high schools.
* Harpswell Coastal Academy had its first graduating cohort later.
tabulate school_level _merge
gen `x' = inlist(school_level, 0, 1, 2)
list ncessch school_name cohort school_status check if `x' & _merge > 2, ab(32) noobs
assert check == 1 if `x' & _merge > 2
drop if `x'
drop `x'

* Drop all other unmatched school-cohorts in CCD.
* These are elementary schools, merged schools, and closed schools.
* Need to revisit this.
tabulate _merge
list ncessch school_name cohort lowest_grade_offered highest_grade_offered if _merge == 2, ab(32) noobs
drop if _merge == 2
assert _merge > 2
drop _merge

* Set aside for merge.
tempfile sch
save `sch'

********************************************************************************
* Load mass layoffs.
********************************************************************************

* Read WARN data.
import excel "`WRN'", firstrow clear
describe
isid id

* Drop flagged events.
assert inlist(excl, 0, 1)
tabulate excl
drop if excl

* Merge onto site-school pairs.
preserve
  import delimited "`LOC'", clear
  describe
  isid id ncessch year
  tempfile loc
  save `loc'
restore
merge 1:m id using `loc', assert(3) nogen

* Merge onto regional characteristics.
preserve
  import delimited "`ACS'", clear
  describe
  isid year county tract
  gen geoid = strofreal(state, "%02.0f") + strofreal(county, "%03.0f") + strofreal(tract, "%06.0f")
  destring geoid, replace
  quietly ds
  local acsvarlist = r(varlist)
  tempfile acs
  save `acs'
restore
joinby geoid year using `acs', unmatched(master)

* Drop SY 20-21 cohort. Need to update tracts for 2020 decennial census.
gen cohort = mod(year, 100) * 100 + mod(year, 100) + 1
tabulate cohort _merge
drop if cohort == 2021
assert _merge == 3
drop _merge

* Calculate time between cohort graduation and notification date.
gen grad = mdy(7, 1, year)
gen diff = datediff(grad, date, "month")

* Drop cohorts that precede the WARN data.
tabstat diff, by(cohort) statistics(N min max) nototal
bysort cohort: egen diff_min = min(diff)
levelsof cohort if -6 < diff_min, local(censorlist) sep(,)
drop if inlist(cohort, `censorlist')

* Calculate total mass layoff dosage.
gen dosage = layoffs / den_emp / ceil(dist / avg_commute)
foreach m of numlist 6 12 24 {
  bysort ncessch cohort: egen layoff`m' = total(dosage * inrange(diff, `m' - 12, `m'))
}

* Bring to school-cohort level.
keep ncessch cohort layoff6 layoff12 layoff24 `acsvarlist'
duplicates drop
isid ncessch cohort

* Merge onto cohort characteristics.
* Note unmatched cohorts are left-censored in the WARN data.
merge 1:1 ncessch cohort using `sch', keep(2 3)
tabulate cohort _merge
assert (_merge == 2) == inlist(cohort, `censorlist', 2021)
drop if _merge == 2
drop _merge

********************************************************************************
* Construct additional measures.
********************************************************************************

* Missing enrollment.
assert cohort_sex_total == cohort_race_total
rename cohort_sex_total cohort_enrl
drop cohort_race_total
egen cohort_demo_mi = anymatch(lowest_grade_offered highest_grade_offered), values(-2)
assert lowest_grade_offered == highest_grade_offered if cohort_demo_mi

* Title I status.
assert !mi(title_i_status)
tabulate title_i_status
gen titlei = inrange(title_i_status, 1, 5) if title_i_status > 0

* Free or reduced price lunch.
tabulate title_i_status free_or_reduced_price_lunch if free_or_reduced_price_lunch < 0
gen     cohort_frpl = free_or_reduced_price_lunch
replace cohort_frpl = cohort_enrl if cohort_frpl < 0 & title_i_status == 1
replace cohort_frpl = 0 if cohort_frpl < 0

* Transform counts to proportions of cohort.
foreach x in sex_female race_black race_hisp frpl {
  local y = regexr("`x'", "(sex|race)_", "")
  gen pct_`y' = cohort_`x' / cohort_enrl
}
foreach m of numlist 6 12 24 {
  gen pct_grad`m' = max(n_grad`m' / cohort_enrl, 1)
  gen pct_coll`m' = n_coll`m' / n_grad`m'
  gen pct_coll_2yr`m' = n_coll_2yr`m' / n_grad`m'
  gen pct_coll_4yr`m' = n_coll_4yr`m' / n_grad`m'
}

* Rural school.
assert !mi(urban_centric_locale)
tabulate urban_centric_locale
gen rural = inlist(urban_centric_locale, 41, 42, 43)

* Regional educational attainment.
egen pct_educ_coll = rowtotal(pct_educ_aa pct_educ_ba pct_educ_ma)

* Log median household income.
gen log_p50_hhinc = ln(p50_hhinc)

* Proficiency rates.
foreach var of varlist pct_prof_* {
  replace `var' = .m if `var' < 0
  quietly summarize `var'
  assert 1 < r(max) & r(max) <= 100
  replace `var' = `var' / 100
}

* Reshape to school-cohort-followup level.
reshape long layoff pct_grad pct_coll pct_coll_2yr pct_coll_4yr, i(ncessch cohort) j(months)

* Write to disk.
quietly putlabels using "`VAR'", drop order
quietly compress
save "`OUT'", replace

* Close the log.
log close
