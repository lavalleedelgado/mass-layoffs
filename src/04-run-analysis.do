version 18
clear all
set type double
set linesize 120

********************************************************************************
* Set up.
********************************************************************************

* Identify inputs and outputs.
local PWD "`c(pwd)'"
local LOG "`PWD'/src/04-run-analysis.log"
local ADO "`PWD'/src/ado"
local VAR "`PWD'/in/varlist.xlsx"
local DTA "`PWD'/out/analysis.dta"
local OUT "`PWD'/out"

* Add project commands to the path.
adopath ++ "`ADO'"

* Start the log.
capture log close
log using "`LOG'", replace

********************************************************************************
*
* Project:  Mass layoffs
* Purpose:  Run analysis
* Author:   Patrick Lavallee Delgado
* Created:  19 December 2023
*
* Notes:
*
* To do:
*
********************************************************************************

* Identify outcomes, covariates, and periods.
local Y pct_add pct_grad pct_coll pct_coll_2yr pct_coll_4yr
local X pct_female pct_black pct_hisp pct_prof_math pct_prof_math_mi pct_prof_read pct_prof_read_mi pct_frpl
local G titlei rural pct_educ_hs pct_educ_coll pct_unemp pct_naics_31_33 log_p50_hhinc
local T 3 12 24

* Load analysis file.
use "`DTA'", clear
describe
isid ncessch cohort
xtset ceeb cohort, delta(101)

* Calculate summary statistics.
local table1 pct_add pct_*_3mo signal_3mo `X' `G'
crosstab `table1' using "`OUT'/table1.xlsx", statistics(N mean sd min p5 q p95 max)

* Set coefficients on signal in same row.
gen signal = .
label variable signal "Mass layoff signal"
local options rename(signal_[0-9]+mo signal) keep(*.signal)

* Set value labels for interaction with rurality.
label variable rural "Rural school"
label define rural_vlab 0 "Non-rural" 1 "Rural"
label values rural rural_vlab

* Estimate cohort retention impacts.
gettoken y Y : Y
assert "`y'" == "pct_add"
eststo: regress D.(`y' signal_3mo `X' `G'), vce(cluster ceeb)
eststo: regress D.`y' Dc.signal_3mo#i.rural D.(`X' `G'), vce(cluster ceeb)
modeltab using "`OUT'/primary-`y'.tex", `options' barebones noobs
estimates clear

* Estimate postsecondary impacts statewide and by rurality.
foreach y of local Y {
  foreach t of local T {
    eststo: regress D.(`y'_`t'mo signal_`t'mo `X' `G'), vce(cluster ceeb)
    eststo: regress D.`y'_`t'mo Dc.signal_`t'mo#i.rural D.(`X' `G'), vce(cluster ceeb)
    test 0.rural#Dc.signal_`t'mo = 1.rural#Dc.signal_`t'mo
  }
  modeltab using "`OUT'/primary-`y'.tex", `options' barebones noobs
  estimates clear
}

* Close the log.
log close
