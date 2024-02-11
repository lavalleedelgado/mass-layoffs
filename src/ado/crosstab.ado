*! version 1.3, Patrick Lavallee Delgado, October 2024

capture program drop crosstab
program define crosstab, rclass

  ******************************************************************************
  *
  * crosstab
  *
  * To do:  Write documentation.
  *         Draw fewer borders.
  *         Export to Latex.
  *
  ******************************************************************************

  quietly {

  * Start timer.
  local start = now()

  * Parse arguments.
  syntax [varlist(numeric fv)] [if] [in] using/ [fweight aweight], [ ///
    sheet(string) ///
    by(string asis) ///
    Statistics(namelist) ///
    VARnames NOVARnames ///
    TEST NOTEST equivalence ///
    HIghlight NOHIghlight ///
    STARSlevels(numlist max=3 >=0 <=1 sort) nostars ///
    OVERALLlabel(string) nooverall ///
    nolabel nobinarylabels ///
    format(string) barebones ///
  ]

  * Mark observations.
  marksample touse, novarlist strok
  local mastervarlist : list uniq varlist

  * Parse weights.
  if "`weight'" != "" {
    tempvar weightvar
    gen `weightvar' `exp'
    local wgt `weight' = `weightvar'
  }

  * Check destination.
  local out `using'
  capture assert regexm("`out'", "\.(xlsx?|tex)$")
  if _rc {
    display as error "destination file must be Excel workbook or LaTeX file"
    error _rc
  }

  * Check worksheet name.
  if mi("`sheet'") local sheet Sheet1
  capture assert strlen("`sheet'") <= 31
  if _rc {
    display as error "Excel worksheet name length cannot exceed 31 characters"
    error _rc
  }

  * Check statistics.
  local SUMMARY_STATISTICS N missing mean sum sum_w min max range sd variance cv semean skewness kurtosis p1 p5 p10 p25 median p50 p75 p90 p95 p99 iqr
  local clusters
  if mi("`statistics'") {
    local statistics N missing mean
  }
  else {
    local statistics : subinstr local statistics "q" "p25 p50 p75", all word
    local statistics : list uniq statistics
    foreach var in `: list statistics - SUMMARY_STATISTICS' {
      capture confirm variable `var'
      if _rc {
        display as error "cluster variable not found: `var'"
        error 111
      }
      local clusters `clusters' `var'
    }
  }

  * Set default variable names option.
  local varnames `varnames' `novarnames'
  if mi("`varnames'") local varnames novarnames
  opts_exclusive "`varnames'"

  * Set default test option.
  local test `test' `notest'
  if mi("`test'") local test notest
  opts_exclusive "`test'"

  * Set default highlight option.
  local highlight `highlight' `nohighlight'
  if mi("`highlight'") local highlight highlight
  opts_exclusive "`highlight'"

  * Set default significance levels option.
  if mi("`starslevels'") local starslevels 0.001 0.01 0.05

  * Set default overall options.
  if mi("`by'", "`overall'") local overall overall
  if mi("`overalllabel'") local overalllabel Overall

  * Set default format for LaTeX numbers.
  if "`format'" == "" local format %20.8f
  local dformat = ustrregexrf("`format'", "\.[0-9]+", ".0")

  * Parse groups.
  local 0 `by'
  syntax [varlist(default=none fv)] [if] [in], [equivalence MIssing NOEMIssing]
  local masterbyslist `varlist'
  if `: word count `masterbyslist'' > 1 local highlight nohighlight

  * Override options for equivalence table.
  if "`equivalence'" == "equivalence" {
    local statistics N mean
    local varnames novarnames
    local test test
    local overall nooverall
  }

  ******************************************************************************
  * Prepare data.
  ******************************************************************************

  * Get current frame.
  pwf
  local pwf = r(currentframe)

  * Initialize results frame.
  tempname stats
  frame create `stats' long(varid byid) str80(varname) str32(stat) double(value)

  * Initialize labels file.
  tempname names
  frame create `names' str80(varname) str240(varlabel)

  * Initialize tests file.
  tempname tests
  frame create `tests' long(varid) str32(byname) double(diff sediff pval)

  * Copy variables and observations to a new frame.
  tempname tmp
  fvrevar `mastervarlist' `clusters' `masterbyslist' `weightvar', list
  frame put `r(varlist)' if `touse', into(`tmp')
  cwf `tmp'
  capture assert c(N)
  if _rc error 2000

  * Drop value labels if requested.
  if "`label'" == "nolabel" {
    label values `mastervarlist' .
  }

  * Drop binary value labels if requested.
  if "`binarylabels'" == "nobinarylabels" {
    foreach var of local mastervarlist {
      local vlab : value label `var'
      if "`vlab'" != "" {
        label list `vlab'
        if r(k) <= 2 label values `var' .
      }
    }
  }

  ******************************************************************************
  * Prepare data variables.
  ******************************************************************************

  local vars
  local cats

  * Consider each variable.
  foreach var of local mastervarlist {

    * Unpack base variables.
    fvrevar `var', list
    local bvlist = r(varlist)
    local varname = subinstr("`bvlist'", " ", "#", .)

    * Write variable label.
    local varlabel
    foreach bv of local bvlist {
      local lab : variable label `bv'
      if "`lab'" == "" {
        local lab "`bv'"
      }
      if "`varlabel'" != "" {
        local lab "`varlabel' x `lab'"
      }
      local varlabel "`lab'"
    }

    * Register variable.
    local vars `vars' `varname'
    frame post `names' ("`varname'") ("`varlabel'")

    * Expand factor variable list.
    fvexpand `var'
    local fvlist = r(varlist)
    local fvops = r(fvops)

    * Handle missing factor variable notation.
    if "`fvops'" != "true" {
      if "`: value label `var''" != "" {
        local var i.`var'
        fvexpand `var'
        local fvlist = r(varlist)
        local fvops = r(fvops)
      }
    }

    * Finished continuous variable.
    if "`fvops'" != "true" continue

    * Generate indicators for each category.
    foreach fv of local fvlist {

      * Generate indicator.
      local fv = ustrregexra("`fv'", "(?<=[0-9])bo?(?=\.)", "", 1)
      tempvar x
      gen `x' = `fv'

      * Write category indicator label.
      local fvlab
      foreach bv of local bvlist {
        assert ustrregexm("`fv'", "([0-9]+)([bo]+)?\.`bv'", 1)
        local i = ustrregexs(1)
        local lab : label (`bv') `i'
        if "`fvlab'" != "" {
          local lab "`fvlab' x `lab'"
        }
        local fvlab "`lab'"
      }

      * Register indicator.
      local vars `vars' `x'
      frame post `names' ("`x'") ("    `fvlab'")
    }

    * Register variable for chi-squared test.
    local cats `cats' `varname'
  }

  ******************************************************************************
  * Prepare grouping variables.
  ******************************************************************************

  local bys
  local j 1

  * Consider each grouping variable.
  foreach var of local masterbyslist {

    * Initialize new grouping variable.
    tempvar by
    gen `by' = .
    tempname by_vlab
    label values `by' `by_vlab'
    local `by'_levels
    local min = `j' + 1

    * Unpack base variables.
    fvrevar `var', list
    local bvlist = r(varlist)
    local bvlist2 : subinstr local bvlist " " ",", all

    * Write variable label.
    local varlabel
    foreach bv of local bvlist {
      local lab : variable label `bv'
      if "`lab'" == "" {
        local lab "`bv'"
      }
      if "`varlabel'" != "" {
        local lab "`varlabel' x `lab'"
      }
      local varlabel "`lab'"
    }

    * Register variable.
    local bys `bys' `by'
    frame post `names' ("`by'") ("`varlabel'")

    * Handle labels for missing values.
    foreach bv of local bvlist {

      * Get value label.
      local vlab : value label `bv'
      if "`vlab'" == "" {
        tempname vlab
        label values `bv' `vlab'
        summarize `bv'
        local max = r(max)
        local emi = 0
      }
      else {
        label list `vlab'
        local max = r(max)
        local emi = r(hasemiss)
      }

      * Recode extended missing values to integers if requested.
      if "`noemissing'" != "noemissing" & `emi' > 0 {
        levelsof `bv' if `bv' > ., local(emisslist) missing
        foreach i of local emisslist {
          recode `bv' (`i' = `++max')
          local lab : value `vlab' `i'
          label define `vlab' `max' "`lab'", add
        }
      }

      * Recode system missing values to integers if requested.
      if "`missing'" == "missing" {
        recode `bv' (. = `++max')
        label define `vlab' `max' "Missing", add
      }
    }

    * Expand factor variable list.
    fvexpand `var'
    local fvlist = r(varlist)
    local fvops = r(fvops)

    * Handle missing factor variable notation.
    if "`fvops'" != "true" {
      assert "`: value label `var''" != ""
      local var i.`var'
      fvexpand `var'
      local fvlist = r(varlist)
      local fvops = r(fvops)
    }

    * Generate levels for each group.
    assert "`fvops'" == "true"
    foreach fv of local fvlist {

      * Mark level.
      local fv = ustrregexra("`fv'", "(?<=[0-9])bo?(?=\.)", "", 1)
      replace `by' = `++j' if `fv' & !mi(`bvlist2')

      * Write group level label.
      local fvlab
      foreach bv of local bvlist {
        assert ustrregexm("`fv'", "([0-9]+)([bo]+)?\.`bv'", 1)
        local i = ustrregexs(1)
        local lab : label (`bv') `i', strict
        if "`lab'" == "" {
          local lab : display `: format `bv'' `i'
          local lab = strtrim("`lab'")
        }
        if "`fvlab'" != "" {
          local lab "`fvlab' x `lab'"
        }
        local fvlab "`lab'"
      }
      label define `by_vlab' `j' "`fvlab'", add
    }

    * Save range of group levels.
    numlist "`min'/`j'"
    local `by'_levels = r(numlist)
  }

  * Add overall group if requested.
  if "`overall'" != "nooverall" {
    tempvar all
    gen `all' = 1
    local bys `all' `bys'
    tempname all_vlab
    label values `all' `all_vlab'
    label define `all_vlab' 1 "`overalllabel'"
    local `all'_levels 1
  }

  ******************************************************************************
  * Crosstabulate.
  ******************************************************************************

  * Consider each variable.
  forvalues i = 1/`: word count `vars'' {

    * Get the variable and categorical id.
    local var : word `i' of `vars'
    local cat : list posof "`var'" in cats

    * Consider each group and level.
    foreach by of local bys {
      foreach j of local `by'_levels {

        * Handle categorical header.
        if `cat' {
          local stat : word 1 of `statistics'
          frame post `stats' (`i') (`j') ("`var'") ("`stat'") (.)
          continue
        }

        * Get the subgroup size.
        count if `by' == `j'
        local N = r(N)

        * Calculate requested statistics.
        summarize `var' if `by' == `j' [`wgt'], detail
        foreach stat of local statistics {
          if "`stat'" == "missing" {
            local res = 1 - (r(N) / `N')
          }
          else if "`stat'" == "range" {
            local res = r(max) - r(min)
          }
          else if "`stat'" == "variance" {
            local res = r(Var)
          }
          else if "`stat'" == "cv" {
            local res = r(sd) / r(mean)
          }
          else if "`stat'" == "semean" {
            local res = r(sd) / sqrt(r(N))
          }
          else if "`stat'" == "median" {
            local res = r(p50)
          }
          else if "`stat'" == "iqr" {
            local res = r(p75) - r(p25)
          }
          else if `: list stat in SUMMARY_STATISTICS' {
            local res = r(`stat')
          }
          else if `: list stat in clusters' {
            continue
          }
          else {
            display as error "unknown statistic: `stat'"
            error 198
          }
          frame post `stats' (`i') (`j') ("`var'") ("`stat'") (`res')
        }
        foreach cluster of local clusters {
          distinct `cluster' if `by' == `j' & !mi(`var')
          frame post `stats' (`i') (`j') ("`var'") ("`cluster'") (r(ndistinct))
        }
      }

      * Run tests across groups.
      if "`test'" != "notest" & `: word count ``by'_levels'' > 1 {
        capture {

          * Test independence of categories across groups.
          if `cat' {
            tabulate `var' `by' [`wgt'], chi2
            local p = r(p)
            frame post `tests' (`i') ("`by'") (.) (.) (`p')
          }

          * Test difference in means relative to the reference group.
          else {
            local b : word 1 of ``by'_levels'
            regress `var' `b'.`by' [`wgt']
            local d = -r(table)["b", "`b'.`by'"]
            local s = r(table)["se", "`b'.`by'"]
            local p = r(table)["pvalue", "`b'.`by'"]
            frame post `tests' (`i') ("`by'") (`d') (`s') (`p')
          }
        }
      }
    }
  }

  * Include group sample size and share.
  tempname samp
  local sampsize : list posof "N" in statistics
  local sampprop : list posof "mean" in statistics
  foreach by of local bys {
    foreach j of local `by'_levels {
      count if `by' == `j'
      local n = r(N)
      if `sampsize' {
        frame post `stats' (0) (`j') ("`samp'") ("N") (`n')
      }
      if `sampprop' {
        local p = `n' / c(N)
        frame post `stats' (0) (`j') ("`samp'") ("mean") (`p')
      }
    }
  }

  ******************************************************************************
  * Make table.
  ******************************************************************************

  * Switch to results frame.
  cwf `stats'
  isid varid byid stat

  * Transform to variable level.
  reshape wide value, i(varid byid) j(stat) string
  rename value* *
  reshape wide `statistics', i(varid) j(byid)

  * Include tests.
  if "`test'" != "notest" {

    * Switch to tests frame.
    cwf `tests'

    * Set significance level.
    gen stars = ""
    foreach a of numlist `starslevels' {
      replace stars = stars + "*" if pval < `a'
    }

    * Transform to variable level.
    reshape wide diff sediff pval stars, i(varid) j(byname) string

    * Join onto results.
    cwf `stats'
    frlink 1:1 varid, frame(`tests')
    frget diff* sediff* pval* stars*, from(`tests')
  }

  * Label rows.
  frlink m:1 varname, frame(`names')
  frget varlabel, from(`names')
  assert mi(varlabel) == !varid
  replace varname   = ""            if !varid
  replace varlabel  = "Sample size" if !varid

  * Label columns.
  label variable varlabel "Variable"
  label variable varname  "Variable name"

  * Collect variable list in order.
  local varlist varlabel
  foreach by of local bys {
    foreach j of local `by'_levels {
      foreach stat of local statistics {
        local varlist `varlist' `stat'`j'
      }
    }
    if "`test'" != "notest" & "`by'" != "`all'" {
      local varlist `varlist' diff`by' sediff`by' pval`by'
      if "`stars'" != "nostars" local varlist `varlist' stars`by'
    }
  }
  if "`varnames'" != "novarnames" {
    local varlist varname `varlist'
  }

  * Clean up.
  sort varid
  keep `varlist'
  order `varlist'
  compress

  ******************************************************************************
  * Write to Excel workbook.
  ******************************************************************************

  if regexm("`out'", "\.xlsx?$") {

  * Set row number anchors per number of group variables.
  local r = cond("`bys'" == "`all'", 3, 4)
  local h3 = `r'  - 1
  local h2 = `h3' - 1
  local h1 = `h2' - 1

  * Save to the workbook and initialize a handler for formatting.
  export excel "`out'", sheet("`sheet'", replace) firstrow(varlabels) cell(A`h3')
  putexcel set "`out'", sheet("`sheet'") open modify

  * Write and format column headers.
  foreach by of local bys {
    local superlist
    foreach j of local `by'_levels {
      local sublist
      frame `tmp': local lab2 : label (`by') `j'
      local lab3
      foreach stat of local statistics {
        local sublist `sublist' `stat'`j'
        local lab3 `lab3' `stat'
      }
      local superlist `superlist' `sublist'
      xlfmt header `h2' `sublist', start(A`r') label("`lab2'") merge hcenter bold
      xlfmt header `h3' `sublist', start(A`r') label("`lab3'") hcenter italic
      xlfmt cols `: word 1 of `sublist'', start(A`r') border(left) headerrows
    }
    if `h1' & "`by'" != "`all'" {
      frame `names': levelsof varlabel if varname == "`by'", local(lab1)
      assert `: word count `lab1'' == 1
      xlfmt header `h1' `superlist', start(A`r') label(`lab1') merge hcenter bold
    }
  }

  * Set column widths.
  ds, has(type str#)
  foreach col in `r(varlist)' {
    local width = regexr("`: type `col''", "^str", "")
    local width = max(16, min(`width', 80))
    xlfmt cols `col', colwidth(`width')
  }

  * Format numbers.
  ds, has(type byte int long)
  local integers = r(varlist)
  if !mi("`integers'") xlfmt cols `integers', start(A`r') nformat(0)
  ds, has(type float double)
  local decimals = r(varlist)
  if !mi("`decimals'") xlfmt cols `decimals', start(A`r') nformat(0.00)

  * Format tests.
  if "`test'" != "notest" {
    foreach by of local bys {
      if "`by'" == "`all'" continue
      local sublist diff`by' sediff`by' pval`by'
      xlfmt header `h2' `sublist', start(A`r') label("Difference") merge hcenter bold
      xlfmt header `h3' `sublist', start(A`r') label("diff se p") hcenter italic
      xlfmt cols `: word 1 of `sublist'', start(A`r') border(left) headerrows
      xlfmt cols pval`by', start(A`r') nformat(0.000)
      if "`stars'" != "nostars" {
        xlfmt header `h2' stars`by', start(A`r') label(" ")
        xlfmt header `h3' stars`by', start(A`r') label("stars") hcenter italic
      }
      if "`highlight'" != "nohighlight" {
        local n : word count `starslevels'
        local sig : word `n' of `starslevels'
        xlfmt rows pval`by' < `sig', start(A`r') fpattern(solid, yellow)
      }
    }
  }

  * Add borders around row headers.
  * xlfmt rows ustrregexm(varlabel, "^[^\s]"), start(A`r') border(top)
  * xlfmt rows ustrregexm(varlabel, "^[^\s]"), start(A`r') border(bottom)

  * Freeze row and column labels.
  local --r
  local c = cond("`varnames'" != "novarnames", 2, 1)
  putexcel sheetset, split(`r', `c')

  * Close the worksheet.
  putexcel save
  putexcel clear

  }

  ******************************************************************************
  * Write to LaTeX.
  ******************************************************************************

  if regexm("`out'", "\.tex$") {

  * Initialize table file.
  tempname f
  file open `f' using "`out'", write replace

  * Count statistics.
  local statistics : subinstr local statistics "N" "", word all
  local nstat : word count `statistics'

  * Start table.
  if "`barebones'" != "barebones" {

    * Write column specification.
    local ncols 0
    foreach by of local bys {
      local `by'_k = `nstat' * `: word count ``by'_levels''
      if "`test'" != "notest" & "`by'" != "`all'" {
        local ++`by'_k
      }
      local ncols = `ncols' + ``by'_k'
    }
    local colspec = "S" * `ncols'
    file write `f' "\begin{tabular}{l`colspec'}" _n
    file write `f' _col(3) "\hline\hline \\ [-0.5 em]" _n

    * Write group headers.
    if "`bys'" != "`all'" {
      local header
      local midrule
      local k 2
      foreach by of local bys {
        frame `names': levelsof varlabel if varname == "`by'", local(lab)
        assert `: word count `lab'' == 1
        local lab = `lab'
        local header "`header' & \multicolumn{``by'_k'}{c}{`lab'}"
        local m = `k' + ``by'_k' - 1
        local midrule "`midrule' \cmidrule(lr){`k'-`m'}"
        local k = `m' + 1
      }
      file write `f' _col(3) "`header' \\ [0.5 em]" _n
      file write `f' _col(3) "`midrule' \\ [-0.75 em]" _n
    }

    * Write subgroup headers.
    local header
    foreach by of local bys {
      foreach j of local `by'_levels {
        frame `tmp': local lab : label (`by') `j'
        local header "`header' & \multicolumn{`nstat'}{c}{`lab'}"
      }
      if "`test'" != "notest" & "`by'" != "`all'" {
        local header "`header' & \multicolumn{1}{c}{$\Delta$}"
      }
    }
    file write `f' _col(3) "`header' \\ [0.5 em]" _n

    * Write statistic headers.
    if `nstat' > 1 {
      local header
      foreach by of local bys {
        foreach j of local `by'_levels {
          foreach stat of local statistics {
            local header "`header' & \multicolumn{1}{c}{`stat'}"
          }
        }
        if "`test'" != "notest" & "`by'" != "`all'" {
          local header "`header' &"
        }
      }
      file write `f' _col(3) "`header' \\ [0.5 em]" _n
    }
    file write `f' _col(3) "\hline \\ [-0.5 em]" _n
  }

  * Get numbers to format as integers.
  ds, has(type byte int long)
  local integers = r(varlist)

  * Write table data.
  forvalues i = 2/`c(N)' {

    * Format row label.
    local rowlabel = varlabel[`i']
    local rowlabel = ustrregexra("`rowlabel'", "_", "\\_", 1)
    local rowlabel = ustrregexra("`rowlabel'", "&", "\\&", 1)
    local rowlabel = ustrregexrf("`rowlabel'", "^[\s]{4}", "\\quad ")

    * Collect row data.
    local row
    local ses
    foreach by of local bys {

      * Format statistics.
      foreach j of local `by'_levels {
        foreach stat of local statistics {
          local var `stat'`j'
          local int : list posof "`var'" in integers
          local fmt = cond(`int', "`dformat'", "`format'")
          local val : display `fmt' `var'[`i']
          if mi(`val') local val
          local row "`row' & `val'"
          local ses "`ses' &"
        }
      }

      * Format tests.
      if "`test'" != "notest" & "`by'" != "`all'" {

        * Format difference.
        local b : display `format' diff`by'[`i']
        local sig = stars`by'[`i']
        if mi(`b') {
          local b
          local sig = ustrregexra("`sig'", "\*", "†")
        }
        local row "`row' & `b'{`sig'}"

        * Format standard error.
        local se : display `format' sediff`by'[`i']
        if mi(`se') local se
        else        local se (`se')
        local ses "`ses' & `se'"
      }
    }

    * Write rows.
    if "`test'" == "notest" {
      file write `f' _col(3) "`rowlabel' `row' \\ [0.5 em]" _n
    }
    else {
      file write `f' _col(3) "`rowlabel' `row' \\" _n
      file write `f' _col(3) "`ses' \\ [0.5 em]" _n
    }
  }

  * Write sample size if requested.
  if `sampsize' {
    local row
    foreach by of local bys {
      foreach j of local `by'_levels {
        local val : display `dformat' N`j'[1]
        local row "`row' & `val'"
      }
      if "`test'" != "notest" {
        local row "`row' &"
      }
    }
    file write `f' _col(3) "\hline \\ [-0.5 em]" _n
    file write `f' _col(3) "Sample size `row' \\ [0.5 em]" _n
  }

  * Finish table.
  if "`barebones'" != "barebones" {
    file write `f' _col(3) "\hline\hline" _n
    file write `f' "\end{tabular}" _n
  }

  * Close table file.
  file close `f'

  }

  * Return calling frame.
  cwf `pwf'

  * Report total time elapsed.
  local timer = now() - `start'
  local timer : display %-tcHH:MM:SS `timer'
  return local timer = "`timer'"

  }

end
