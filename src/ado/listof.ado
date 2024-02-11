*! version 1.0, Patrick Lavallee Delgado, August 2023

capture program drop listof
program define listof, rclass

  ******************************************************************************
  *
  * listof
  *
  * Read variables into macro lists. Unlike the -levelsof- command, this
  * implementation does not deduplicate and preserves element order.
  *
  * listof [varlist] [if] [in] [using filename], [clean options]
  *
  * varlist: variables to list into macro lists of the same name
  * using: path to control file if not the current dataset
  * clean: whether to retokenize with minimal adornment
  * verbose: print control file to console
  * options: options to pass to -import delimited- or -import excel-
  *
  ******************************************************************************

  quietly {

  * Parse arguments for path to control file and options.
  noisily syntax anything(everything), [clean Verbose *]
  local u = strpos(`"`anything'"', "using")
  if `u' {
    local using = substr(`"`anything'"', `u', strlen(`"`anything'"') - `u' + 1)
    gettoken kw using : using
    assert "`kw'" == "using"
    local using = `using'
    local anything = substr(`"`anything'"', 1, `u' - 1)
  }

  * Get current frame.
  pwf
  local pwf = r(currentframe)

  * Current dataset is control file if none given.
  if mi("`using'") {
    tempfile using
    save `using'
  }

  * Switch to new frame.
  tempname tmp
  mkf `tmp'
  cwf `tmp'

  * Read control file.
  if regexm("`using'", "\.[tc]sv") {
    import delimited "`using'", `options'
  }
  else if regexm("`using'", "\.xlsx?") {
    import excel "`using'", `options'
  }
  else {
    use "`using'"
  }

  * Parse arguments for variable list and observation restriction.
  local 0 `anything'
  noisily syntax [varlist] [if] [in]

  * Keep selected variables and observations.
  capture keep `if' `in'
  keep `varlist'

  * Print control file if requested.
  if !mi("`verbose'") noisily list, noobs ab(32)

  * Return list item count.
  local N = c(N)
  return local N "`N'"

  capture {

  * Load macro lists.
  foreach var of local varlist {
    local list
    forvalues i = 1/`N' {
      local item = `var'[`i']
      local list "`list' `"`item'"'"
    }
    if !mi("`clean'") {
      local list : list clean list
      return local `var' `list'
    }
    else {
      return local `var' `"`list'"'
    }
  }

  }

  * Clean up.
  cwf `pwf'
  exit _rc

  }

end
