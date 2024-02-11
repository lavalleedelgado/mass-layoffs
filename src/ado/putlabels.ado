*! version 1.0, Patrick Lavallee Delgado, September 2023

capture program drop putlabels
program define putlabels

  ******************************************************************************
  *
  * putlabels
  *
  * Set variable names, value labels, and formats from a control file given as
  * an Excel workbook. Optionally drop variables not specified.
  *
  ******************************************************************************

  quietly {

  * Parse arguments.
  syntax using/, [ ///
    variables(string) varname(string) varlabel(string) vallabel(string) series(string) format(string) ///
    values(string) value(string) label(string) ///
    DROP NODROP ORDER NOORDER REPLACE ///
    keepif(string asis) ///
  ]

  * Check control file is an Excel workbook.
  capture assert regexm("`using'", "\.xlsx?$")
  if _rc {
    display as error "control file must be Excel workbook"
    exit _rc
  }

  * Set default sheet and column names.
  foreach x in variables varname varlabel vallabel series format values value label {
    if mi("``x''") local `x' `x'
  }

  * Enforce mutually exclusive options.
  foreach x in drop order {
    local `x' ``x'' `no`x''
    opts_exclusive "``x''"
  }

  ******************************************************************************
  * Load variable list.
  ******************************************************************************

  * Get current frame.
  pwf
  local pwf = r(currentframe)

  * Read variable list into new frame.
  tempname tmp
  mkf `tmp'
  cwf `tmp'
  import excel "`using'", sheet(`variables') firstrow
  isid `varname'

  * Restrict variable list if requested.
  if "`keepif'" != "" {
    keep if `keepif'
  }

  * Expand series of variables.
  tempvar idx k j
  gen `idx' = _n
  split `series', gen(`k')
  reshape long `k', i(`varname') j(`j')
  drop if mi(`k') & `j' > 1
  foreach var of varlist `varname' `varlabel' {
    replace `var' = ustrregexra(`var', "%s", `k', 1)
  }
  isid `varname'
  sort `idx'

  * Check whether to set value labels and formats.
  foreach x in vallabel format {
    capture {
      confirm variable ``x''
      count if !mi(``x'')
      assert r(N)
    }
    local set`x' = cond(_rc, 0, 1)
  }

  ******************************************************************************
  * Make value labels.
  ******************************************************************************

  if `setvallabel' {

    preserve

      * Read value label list.
      import excel "`using'", sheet(`values') firstrow clear
      isid `vallabel' `value' `label'

      * Make value labels.
      forvalues i = 1/`c(N)' {
        local x = `vallabel'[`i']
        local v = `value'[`i']
        local l = `label'[`i']
        label define `x' `v' "`l'", add
      }

      * Set aside value label definitions.
      tempfile defvallabel
      label save using `defvallabel'

    restore

    * Load value labels.
    frame `pwf' {
      include `defvallabel'
      label dir
      local defvallabellist = r(names)
    }

    * Report value labels referenced but not defined in control file.
    levelsof `vallabel', local(refvallabellist)
    local diffvallabellist : list refvallabellist - defvallabellist
    if `: list sizeof diffvallabellist' {
      noisily display "value labels not defined in control file:"
      foreach x of local defvallabellist {
        noisily display _col(4) "`x'"
        replace `vallabel' = "" if `vallabel' = "`x'"
      }
    }
  }

  ******************************************************************************
  * Set variable labels.
  ******************************************************************************

  * Initialize an indicator for existence in the data.
  tempvar ok
  gen `ok' = 0

  * Consider each variable.
  forvalues i = 1/`c(N)' {

    * Check that the variable exists.
    local var = `varname'[`i']
    frame `pwf': capture confirm variable `var'
    replace `ok' = !_rc in `i'
    if _rc continue

    * Set the variable label.
    local x = `varlabel'[`i']
    frame `pwf': label variable `var' "`x'"

    * Set the value label and format.
    if `setvallabel' {
      local x = `vallabel'[`i']
      if !mi("`x'") {
        frame `pwf' {
          local set = "`replace'" == "replace" | "`: value label `var''" == ""
          if `set' label values `var' `x'
        }
      }
    }

    * Set the format.
    if `setformat' {
      local x = `format'[`i']
      if !mi("`x'") {
        frame `pwf' {
          local set = "`replace'" == "replace" | "`: format `var''" == ""
          if `set' format `var' `x'
        }
      }
    }
  }

  * Report variables missing in the data.
  capture assert `ok'
  tab `ok'
  if _rc {
    noisily {
      display "variables not in the data:"
      list `varname' `varlabel' if !`ok', ab(32) noobs
    }
  }

  * Collect extant variables in order.
  keep if `ok'
  local ctrlvarlist
  forvalues i = 1/`c(N)' {
    local var = `varname'[`i']
    local ctrlvarlist `ctrlvarlist' `var'
  }

  * Report variables not anticipated in the data and drop if requested.
  frame `pwf': unab datavarlist : *
  local diffvarlist : list datavarlist - ctrlvarlist
  if `: list sizeof diffvarlist' {
    noisily {
      display "variables not in the control file:"
      foreach var of local diffvarlist {
        display _col(4) "`var'"
      }
    }
    if "`drop'" == "drop" {
      noisily display "dropping these variables"
      frame `pwf': drop `diffvarlist'
    }
  }

  * Reorder variables if requested.
  if "`order'" == "order" {
    frame `pwf': order `ctrlvarlist'
  }

  * Return to calling frame.
  cwf `pwf'

  }

end
