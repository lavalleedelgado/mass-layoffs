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


* Load analysis file.
use "`DTA'", clear
describe
isid ncessch cohort month
xtset ceeb

* Specify outcomes and covariates.
local Y pct_grad pct_coll pct_coll_2yr pct_coll_4yr
local X pct_female pct_black pct_hisp pct_frpl pct_prof_math pct_prof_read rural titlei pct_educ_hs pct_educ_coll pct_unemp pct_naics_31_33 log_p50_hhinc

* Estimate impacts.
foreach y of local Y {
  foreach t in 6 12 24 {
    eststo: xtreg `y' layoff `X' i.cohort if months == `t', fe vce(cluster ceeb)
  }
  modeltab * using "`OUT'/primary-`y'.tex", keep(layoff) barebones
  estimates clear
}

* Estimate heterogenous impacts by rurality.
foreach y of local Y {
  foreach t in 6 12 24 {
    eststo: xtreg `y' c.layoff#i.rural `X' i.cohort if months == `t', fe vce(cluster ceeb)
  }
  modeltab * using "`OUT'/rural-`y'.tex"
  estimates clear
}

* Close the log.
log close
