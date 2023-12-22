*! version 1.1, Patrick Lavallee Delgado, October 2023

capture program drop modeltab
program define modeltab

  quietly {

  ******************************************************************************
  * Set up.
  ******************************************************************************

  * Parse arguments.
  syntax anything using/, [ ///
    stars nostars STARS2(numlist max=3 >=0 <=1 sort) ///
    labels nolabels LABELS2(string asis) ///
    drop(string) keep(string) ///
    margins(varname) ///
    barebones NOTABSPEC NOHLINE ///
    * ///
  ]

  * Specify regular expressions for factor variable coefficient.
  local FNOTATION (([0-9]+)?[cbon]{0,2}\.)
  local FVPATTERN `FNOTATION'?([a-z0-9_]+)

  * Save current estimation results if required.
  if strpos("`anything'", ".") {
    estimates query
    if "`r(name)'" == "" {
      tempname cur
      estimates store `cur'
      local anything : subinstr local anything "." "`cur'", all word
    }
  }

  * Check model names.
  local modellist
  estimates dir
  foreach model in `r(names)' {
    foreach pat of local anything {
      if strmatch("`model'", "`pat'") {
        local modellist `modellist' `model'
        continue, break
      }
    }
  }
  local M : word count `modellist'

  * Check destination.
  capture assert regexm("`using'", "\.tex$")
  if _rc {
    display as error "destination file must be LaTeX"
    error _rc
  }

  * Specify cells only.
  if "`barebones'" != "" {
    local labels  nolabels
    local tabspec notabspec
    local hline   nohline
  }

  * Specify default significance levels.
  local starslevels 0.05 0.01 0.001
  if "`stars2'" != "" local starslevels `stars2'
  if "`stars'" == "nostars" local starslevels
  local n_starslevels : word count `starslevels'

  * Specify default column labels.
  local labellist `labels2'

  * Check only either drop or keep.
  capture opts_exclusive "`"`drop'"'" "`"`keep'"'"
  if _rc {
    display as error "can specify either drop() or keep()"
    error 198
  }

  * Check table type.
  local table regressions
  if "`margins'" != "" {
    local d `margins'
    local table margins
  }

  ******************************************************************************
  * Make regressions table.
  ******************************************************************************

  if "`table'" == "regressions" {

    * Consider each model.
    local estlist
    local depvarlist
    local nlist
    forvalues m = 1/`M' {

      * Get model estimates.
      estimates restore `: word `m' of `modellist''
      local n : display %12.0f `e(N)'

      * Get regression table.
      tempname reg
      __etable `reg', `options'
      matrix coleq `reg' = `m'

      * Register this table, dependant variable, sample size with all others.
      local estlist `estlist' `reg'
      local depvarlist `depvarlist' `e(depvar)'
      local nlist `nlist' & `n'
    }

    * Combine estimates.
    tempname est
    matrix coljoinbyname `est' = `estlist'
    local C `M'

    * Set model column labels.
    if "`labellist'" == "" {
      forvalues m = 1/`M' {
        local labellist "`labellist' "(`m')""
      }
    }
    if "`labellist'" == "depvar" {
      local labellist
      forvalues m = 1/`M' {
        local var : word `m' of `depvarlist'
        local lab : variable label `var'
        local labels "`labels' "`lab'""
      }
    }
  }

  ******************************************************************************
  * Make margins table.
  ******************************************************************************

  if "`table'" == "margins" {

    * Get research groups.
    levelsof `d', local(grplist)
    local K = r(r)
    gettoken c t : grplist
    local grplist `t' `c'

    * Initialize container for sample sizes.
    tempname smp
    matrix `smp' = J(`M', `K', 0)
    local colnames
    forvalues k = 1/`K' {
      local colnames `colnames' `k':n
    }
    matrix colnames `smp' = `colnames'

    * Consider each model.
    local estlist
    forvalues m = 1/`M' {

      * Get model estimates.
      estimates restore `: word `m' of `modellist''
      local depvar `e(depvar)'
      local n : display %12.0f `e(N)'

      * Consider each research group.
      local mgnlist
      forvalues k = 1/`K' {

        * Get group index.
        local g : word `k' of `grplist'

        * Get margin table.
        tempname mgn
        margins `g'.`d'
        matrix `mgn' = r(table)'
        local mgnlist `mgnlist' `mgn'

        * Get sample size.
        count if `g'.`d' & e(sample)
        matrix `smp'[`m', `k'] = r(N)

        * Set row and column names,
        matrix rownames `mgn' = `depvar'
        matrix coleq `mgn' = `k'
      }

      * Combine margins.
      tempname reg
      matrix coljoinbyname `reg' = `mgnlist'
      local estlist `estlist' `reg'
    }

    * Combine estimates.
    tempname est
    matrix rowjoinbyname `est' = `estlist'
    matrix `est' = `est', `smp'
    local C `K'

    * Set margin column labels.
    if "`labellist'" == "" {
      foreach g of numlist `grplist' {
        local lab : label (`d') `g'
        local labellist "`labellist' "`lab'""
      }
    }
  }

  ******************************************************************************
  * Write table.
  ******************************************************************************

  * Initialize table file.
  tempname f
  file open `f' using "`using'", write replace

  * Write column specification.
  if "`tabspec'" != "notabspec" {
    local colspec = "S" * `C'
    file write `f' "\begin{tabular}{l`colspec'}" _n
    file write `f' _col(3) "\hline\hline" _n
  }

  * Write column headers.
  if "`labels'" != "nolabels" {
    local header
    forvalues c = 1/`C' {
      local lab : word `c' of `labellist'
      local header "`header' & \multicolumn{1}{c}{`lab'}"
    }
    file write `f' _col(3) "`header' \\" _n
    file write `f' _col(3) "\hline" _n
  }

  * Write parameter estimates.
  foreach par in `: rowvarlist `est'' {

    * Skip this parameter if omitted or requested.
    if ustrregexm("`par'", "^[0-9]+[obn]+\.", 1) continue
    if "`drop'`keep'" != "" {
      local check 0
      foreach pat in `drop' `keep' {
        if strmatch("`par'", "`pat'") {
          local check 1
          continue, break
        }
      }
      if "`drop'" != "" & `check' == 1 continue
      if "`keep'" != "" & `check' == 0 continue
    }

    * Get parameter label.
    local rowlabel
    local varlist = regexreplace("`par'", "#", " ")
    local K : word count `varlist'
    forvalues k = 1/`K' {

      * Get next name.
      local var : word `k' of `varlist'
      local lab `var'

      * Handle variable.
      capture {
        assert ustrregexm("`var'", "^`FVPATTERN'", 1)
        local var = ustrregexs(3)
        local lvl = ustrregexs(2)
        confirm variable `var'
      }
      if !_rc {
        local lab : variable label `var'
        if "`lvl'" != "" {
          local vlab : value label `var'
          if "`vlab'" != "" {
            local sg : label `vlab' `lvl'
          }
          else {
            local sg : display `: format `var'' `lvl'
            local sg = strtrim("`sg'")
          }
          local lab "`lab': `sg'"
        }
      }

      * Handle intercept.
      else if "`var'" == "_cons" {
        local lab "Intercept"
      }

      * Handle interactions.
      if `k' == 1 {
        local rowlabel `lab'
      }
      else if `k' == 2 {
        local rowlabel (`rowlabel') x (`lab')
      }
      else {
        local rowlabel `rowlabel' x (`lab')
      }
    }

    * Handle regressions table.
    if "`table'" == "regressions" {

      * Get estimates.
      local betas
      local sigmas
      forvalues c = 1/`C' {

        * Format significance level.
        local sig
        if "`stars'" != "nostars" {
          local p = `est'["`par'", "`c':pvalue"]
          foreach a of numlist `starslevels' {
            if `p' < `a' local sig `sig'*
          }
          local sig {`sig'}
        }

        * Format point estimate.
        local b = `est'["`par'", "`c':b"]
        if mi(`b') local b
        local betas `betas' & `b'`sig'

        * Format standard error.
        local se = `est'["`par'", "`c':se"]
        if mi(`se') local se
        else        local se (`se')
        local sigmas `sigmas' & `se'
      }

      * Write rows.
      file write `f' _col(3) "`rowlabel' `betas' \\" _n
      file write `f' _col(3) "`sigmas' \\ [0.5em]" _n
    }

    * Handle margins table.
    if "`table'" == "margins" {

      * Get estimates.
      local betas
      local sigmas
      local ns
      forvalues c = 1/`C' {

        * Format significance level.
        local sig
        if "`stars'" != "nostars" {
          local p = `est'["`par'", "`c':pvalue"]
          foreach a of numlist `starslevels' {
            if `p' < `a' local sig `sig'*
          }
          local sig {`sig'}
        }

        * Format point estimate.
        local b = `est'["`par'", "`c':b"]
        if mi(`b') local b
        local betas `betas' & `b'`sig'

        * Format standard error.
        local se = `est'["`par'", "`c':se"]
        if mi(`se') local se
        else        local se (`se')
        local sigmas `sigmas' & `se'

        * Format sample size.
        local n = `est'["`par'", "`c':n"]
        if mi(`n')  local n
        else        local n [`n']
        local ns `ns' & `n'
      }

      * Write rows.
      file write `f' _col(3) "`rowlabel' `betas' \\" _n
      file write `f' _col(3) "`sigmas' \\" _n
      file write `f' _col(3) "`ns' \\ [0.5em]" _n
    }
  }

  * Write sample sizes for regressions table.
  if "`table'" == "regressions" {
    if "`hline'" != "nohline" {
      file write `f' _col(3) "\hline" _n
    }
    file write `f' _col(3) "Sample size `nlist' \\" _n
  }

  * Finish table.
  if "`tabspec'" != "notabspec" {
    file write `f' _col(3) "\hline" _n
    file write `f' "\end{tabular}" _n
  }

  * Close table file.
  file close `f'

  }

end


program define __etable

  syntax name, [csdid(string) *]
  local out `namelist'

  if "`e(cmd)'" == "csdid" {
    local matlist
    foreach cmd of local csdid {
      estat `cmd'
      tempname mat
      matrix `mat' = r(table)'
      local matlist `matlist' `mat'
    }
    matrix rowjoinbyname `out' = `matlist'
  }

  else {
    ereturn display
    matrix `out' = r(table)'
  }

end
