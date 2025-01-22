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
local NSC "`DTA'/nsc.csv"
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
* To do:    Check imputation of cohort enrollment.
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
import delimited "`NSC'", clear
describe
gen lag = (sy - cohort) / 101
drop sy
isid ceeb cohort lag, missok

* Drop overall state counts.
drop if mi(ceeb)
isid ceeb cohort lag

* Fix bug in NSC processing of Maine Ocean School.
list ceeb school_name cohort lag n_coll_ostate if ceeb == 200003, ab(32) noobs
assert ceeb == 200003 if lag > 3 | mi(n_coll_ostate)
drop if lag > 2
replace n_coll_ostate = 0 if mi(n_coll_ostate)
assert inlist(lag, 0, 1, 2)
foreach var of varlist n_* {
  assert !mi(`var')
}

* Transform to school-cohort level.
recode lag (0 = 3) (1 = 12) (2 = 24)
reshape wide n_*, i(ceeb cohort) j(lag)
rename n_*# n_*_#mo
foreach var of varlist n_* {
  assert !mi(`var')
}

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
assert _merge == 3
drop _merge

* Calculate months between cohort graduation and notification date.
gen grad = mofd(mdy(7, 1, year + 1))
gen diff = mofd(date) - grad

* Drop cohorts that precede the WARN data.
gen cohort = mod(year, 100) * 100 + mod(year, 100) + 1
tabstat diff, by(cohort) statistics(N min max) nototal
bysort cohort: egen diff_min = min(diff)
levelsof cohort if -3 < diff_min, local(censorlist) sep(,)
drop if inlist(cohort, `censorlist')

* Calculate total mass layoff dosage.
gen dosage = layoffs / den_emp / ceil(dist / avg_commute)
foreach m of numlist 3 12 24 {
  bysort ncessch cohort: egen signal_`m'mo = total(dosage * inrange(diff, `m' - 48, `m' - 1) ^ (-1 / (diff - `m')))
}

* Bring to school-cohort level.
keep ncessch cohort signal_*mo `acsvarlist'
duplicates drop
isid ncessch cohort

* Merge onto cohort characteristics.
* Note unmatched cohorts are left-censored in the WARN data.
merge 1:1 ncessch cohort using `sch', keep(2 3)
tabulate cohort _merge
assert (_merge == 2) == inlist(cohort, `censorlist')
drop if _merge == 2
drop _merge

********************************************************************************
* Clean outcomes and covariates.
********************************************************************************

* Treat missing outcomes as zero.
* These are gaps in the NSC data where no student appears to have graduated.
assert !mi(check)
foreach var of varlist n_grad* n_coll* {
  assert check == mi(`var')
  replace `var' = 0 if check
}

* Next cohort enrollment.
* Note this is not validated against NSC counts.
bysort ceeb (cohort): gen `x' = enrl_g11[_n + 1]
gen n_add = `x' - enrl_g11
gen pct_add = n_add / enrl_g11
foreach var of varlist n_add pct_add {
  replace `var' = .s if !enrl_g11
  replace `var' = .m if `var' == .
}
drop enrl_g11 `x'

* Cohort enrollment.
* Use number of graduates in NSC data if missing or too small in CCD data.
rename enrl_g12 enrl
egen `x' = rowmax(n_grad*)
replace enrl = `x' if enrl < `x' | mi(enrl)
assert !mi(enrl)
drop `x'

* Cohort outcomes.
foreach m of numlist 3 12 24 {
  foreach var in grad_`m'mo coll_`m'mo coll_2yr_`m'mo coll_4yr_`m'mo {

    * Log points.
    gen     ln_`var' = ln(n_`var')
    replace ln_`var' = .s if !enrl
    replace ln_`var' = .m if ln_`var' == .

    * Proportions.
    gen     pct_`var' = n_`var' / enrl
    replace pct_`var' = .s if !enrl
    assert inrange(pct_`var', 0, 1) if !mi(pct_`var')
    assert pct_`var' != .
  }
}

* Cohort demographics.
rename (sex_female race_black race_hisp) (n_female n_black n_hisp)
foreach var in female black hisp {
  gen     pct_`var' = n_`var' / enrl
  replace pct_`var' = .s if !enrl
  replace pct_`var' = .m if mi(n_`var') & enrl > 0
  assert inrange(pct_`var', 0, 1) if !mi(pct_`var')
  assert pct_`var' != .
}

* Title I status.
assert !mi(title_i_status)
tabulate title_i_status
gen titlei = inrange(title_i_status, 1, 5) if title_i_status > 0
bysort ceeb (cohort): replace titlei = titlei[_n - 1] if mi(titlei)
assert !mi(titlei)

* Free or reduced price lunch.
assert enrollment > 0 & !mi(enrollment)
assert inrange(free_or_reduced_price_lunch, 0, enrollment)
gen pct_frpl = free_or_reduced_price_lunch / enrollment
assert inrange(pct_frpl, 0, 1)

* Rural school.
assert !mi(urban_centric_locale)
tabulate urban_centric_locale
gen rural = inlist(urban_centric_locale, 41, 42, 43)

* Regional educational attainment and employment patterns.
egen pct_educ_coll = rowtotal(pct_educ_aa pct_educ_ba pct_educ_ma)
foreach var of varlist pct_educ_hs pct_educ_coll pct_unemp pct_naics_* {
  quietly summarize `var'
  assert 1 < r(max) & r(max) <= 100
  replace `var' = `var' / 100
  assert inrange(`var', 0, 1)
}

* Log median household income.
gen log_p50_hhinc = ln(p50_hhinc)
bysort ceeb (cohort): replace log_p50_hhinc = log_p50_hhinc[_n - 1] if mi(log_p50_hhinc)
assert !mi(log_p50_hhinc)

* Proficiency rates.
foreach var of varlist pct_prof_* {
  quietly summarize `var'
  assert 1 < r(max) & r(max) <= 100
  replace `var' = `var' / 100
  gen `var'_mi = !inrange(`var', 0, 1)
  replace `var' = 0 if `var'_mi
}

* Write to disk.
putlabels using "`VAR'", drop order
quietly compress
save "`OUT'", replace

* Close the log.
log close
