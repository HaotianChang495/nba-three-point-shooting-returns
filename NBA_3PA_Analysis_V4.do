*==============================================================================
* The Relationship Between Team Performance and Three-Point Attempt Rate
* Evidence from the NBA (2005-2024)
* Haotian Chang
*
* Input : NBA_Advanced_Stats.csv   (600 franchise-season observations)
*
* Requires: ssc install ftools
*           ssc install require      // reghdfe 6.x dependency
*           ssc install reghdfe
*           ssc install estout
*
* Install in that order. If reghdfe reports a missing dependency, it will
* name the package; install it and re-run the line that failed.
*
* NOTE: run this file SECTION BY SECTION the first time, not all at once.
*==============================================================================

clear all
set more off

*------------------------------------------------------------------------------
* SECTION 1.  Set the working directory, then import.
*------------------------------------------------------------------------------
* Edit the next line to the folder containing the csv, then remove the asterisk.
* cd "/your/path/here"

pwd                       // confirm you are in the right folder
import delimited "NBA_Advanced_Stats.csv", clear varnames(1) case(preserve)

* The 3PA% header is not a legal Stata name (it starts with a digit and
* contains %).  Different Stata versions mangle it differently: some import
* it as v7, others strip the illegal characters and call it PA.  Rather than
* guess the name, locate the column by position.
capture confirm variable tpa
if _rc {
    unab allv : _all
    local v3pa : word 7 of `allv'
    display as text "Column 7 imported as -`v3pa'-; renaming it to -tpa-."
    rename `v3pa' tpa
}

* Safety check: confirm we grabbed the right column rather than a neighbour.
quietly summarize tpa
assert abs(r(min) - .105) < .001 & abs(r(max) - .519) < .001

describe
summarize tpa WinRate ORtg DRtg Pace

* CHECK: tpa should range from .105 to .519 with a mean of about .288

*------------------------------------------------------------------------------
* SECTION 2.  Panel setup.
*   Use FranchiseID, not Team.  Team has 35 values because relocations and
*   renamings were never merged (SEA->OKC, NJN->BKN, CHA Bobcats->Hornets,
*   NOH->NOP).  Franchise fixed effects must absorb 30 entities, not 35.
*------------------------------------------------------------------------------
encode FranchiseID, gen(fid)
xtset fid Season

assert _N == 600

quietly levelsof fid, local(F)
local nfranch : word count `F'
display as result "Observations: " _N "   Franchises: `nfranch'"
assert `nfranch' == 30

* CHECK: "Observations: 600   Franchises: 30"

xtdescribe                // every franchise should appear in all 20 seasons

*------------------------------------------------------------------------------
* SECTION 3.  Derived terms.
*   YearIndex is centered at 10.5 to reduce collinearity among the interaction
*   terms.  Centering does not change the fit or any marginal effect.
*------------------------------------------------------------------------------
gen double yc     = YearIndex - 10.5
gen double tpa2   = tpa^2
gen double tpa_y  = tpa*yc
gen double tpa_y2 = tpa*yc^2

label var tpa    "3PA%"
label var tpa2   "3PA% squared"
label var tpa_y  "3PA% x YearIndex(c)"
label var tpa_y2 "3PA% x YearIndex(c) squared"

*------------------------------------------------------------------------------
* SECTION 4.  Headline specification.
*   Linear in 3PA%, two-way fixed effects, NO performance controls.
*   ORtg and DRtg are post-treatment mediators and are deliberately excluded.
*------------------------------------------------------------------------------
reghdfe WinRate tpa, absorb(fid Season) vce(cluster fid)
estimates store c2

display as result "Effect of +1pp in 3PA% on win rate = " %6.4f _b[tpa]/100
display as result "Equivalent wins over 82 games      = " %6.3f 82*_b[tpa]/100

* CHECK: coefficient 0.968, clustered SE 0.237, p < 0.001
*        +1pp -> 0.0097 win rate -> about 0.79 wins

*------------------------------------------------------------------------------
* SECTION 5.  The five specifications of Table 3.
*------------------------------------------------------------------------------
reghdfe WinRate tpa tpa2, noabsorb vce(cluster fid)
estimates store c1

* c2 already stored in SECTION 4

reghdfe WinRate tpa tpa2, absorb(fid Season) vce(cluster fid)
estimates store c3

reghdfe WinRate tpa tpa2 tpa_y tpa_y2, absorb(fid Season) vce(cluster fid)
estimates store c4

reghdfe WinRate tpa tpa2 tpa_y tpa_y2 ORtg DRtg Pace, ///
        absorb(fid Season) vce(cluster fid)
estimates store c5

esttab c1 c2 c3 c4 c5, se star(* 0.05 ** 0.01 *** 0.001) ///
    stats(N r2 r2_within, labels("N" "R-squared" "Within R-squared")) ///
    mtitles("Quadratic" "Linear+FE" "Quad+FE" "Full+FE" "Full+FE+controls") ///
    title("Table 3. Three-Point Attempt Rate and Win Rate")

*------------------------------------------------------------------------------
* SECTION 6.  Joint tests on the preferred specification, column (4).
*   These are the tests the paper states.  Note that b3 = b4 = 0 is a JOINT
*   hypothesis and requires an F test, not two separate t tests.
*------------------------------------------------------------------------------
estimates restore c4

test tpa_y tpa_y2                    // H0: no time variation      F = 1.62
test tpa2                            // H0: no curvature           F = 1.66
test tpa tpa2 tpa_y tpa_y2           // H0: no effect at all       F = 8.35

*------------------------------------------------------------------------------
* SECTION 7.  Time-varying marginal effect (Table 4, columns 3-5).
*   ME(t) = b1 + 2*b2*3PA% + b3*yc + b4*yc^2, evaluated at each season's
*   league-mean attempt rate.  Standard errors by the delta method.
*
*   lincom with a custom linear combination fails after reghdfe ("not
*   possible with test", r(131)), so the delta method is done directly with
*   matrices: ME = g*b' and Var(ME) = g*V*g', where g is the gradient of the
*   marginal effect with respect to the four strategy coefficients.
*
*   Inference uses t(29): reghdfe treats the franchise FE as redundant for
*   the dof computation because they are nested within the clusters, so the
*   residual dof equals the number of clusters minus one.
*
*   CAREFUL: in Stata, ^ binds more tightly than unary minus, so -9.5^2
*   evaluates to -90.25.  The parentheses in (`ycv')^2 below are required.
*------------------------------------------------------------------------------
estimates restore c4
matrix b = e(b)
matrix V = e(V)

local ib   = colnumb(b, "tpa")
local ib2  = colnumb(b, "tpa2")
local ib3  = colnumb(b, "tpa_y")
local ib4  = colnumb(b, "tpa_y2")
assert !missing(`ib', `ib2', `ib3', `ib4')

quietly levelsof Season, local(yrs)
display as result _n "Season   mean3PA%        ME        SE        p"
foreach y of local yrs {
    quietly summarize tpa if Season == `y', meanonly
    local xb  = r(mean)
    local ycv = `y' - 2014.5

    matrix g = J(1, colsof(b), 0)
    matrix g[1,`ib' ] = 1
    matrix g[1,`ib2'] = 2*`xb'
    matrix g[1,`ib3'] = `ycv'
    matrix g[1,`ib4'] = (`ycv')^2

    matrix mE = g*b'
    matrix mV = g*V*g'
    local me = mE[1,1]/100
    local se = sqrt(mV[1,1])/100
    local pv = 2*ttail(e(df_r), abs(`me'/`se'))

    display as result "`y'     " %8.3f `xb' "  " %8.4f `me' "  " %8.4f `se' ///
                      "  " %6.3f `pv'
}

* CHECK: 2005 ME = +0.0113  (if this is NEGATIVE, the ^2 parentheses are wrong)
*        2008 ME = +0.0125   2020 ME = +0.0081   2024 ME = -0.0013

*------------------------------------------------------------------------------
* SECTION 8.  Unrestricted alternative (Table 4, columns 6-7).
*   A separate 3PA% slope for every season; no functional form imposed.
*
*   CAREFUL: use ibn.Season, not i.Season.  With i.Season the base year is
*   dropped and you get 19 slopes instead of 20.
*------------------------------------------------------------------------------
reghdfe WinRate c.tpa#ibn.Season, absorb(fid Season) vce(cluster fid)
estimates store cflex

* CHECK: the output table should have 20 rows, one per season

testparm c.tpa#ibn.Season            // H0: all 20 slopes zero   F = 2.53, p = .011

* H0: all 20 slopes equal one another
quietly levelsof Season, local(yrs)
local first : word 1 of `yrs'
local cons ""
foreach y of local yrs {
    if `y' != `first' local cons "`cons' (`first'.Season#c.tpa = `y'.Season#c.tpa)"
}
test `cons'                          // F = 0.97, p = 0.514

*------------------------------------------------------------------------------
* SECTION 9.  Robustness of the headline result.
*------------------------------------------------------------------------------
reghdfe WinRate tpa if !inlist(Season,2020,2021), absorb(fid Season) vce(cluster fid)
reghdfe WinRate tpa if Season <= 2019,            absorb(fid Season) vce(cluster fid)
reghdfe WinRate tpa if Season >= 2015,            absorb(fid Season) vce(cluster fid)
reghdfe WinRate tpa Pace,                         absorb(fid Season) vce(cluster fid)
reghdfe WinRate tpa,                              absorb(fid Season) vce(robust)

* No fixed effects at all (the first row of the README summary table)
reghdfe WinRate tpa, noabsorb vce(cluster fid)

* 35 raw team names instead of 30 franchises
encode Team, gen(tid)
reghdfe WinRate tpa, absorb(tid Season) vce(cluster tid)

* The bad-control demonstration: adding the mediators kills the effect
reghdfe WinRate tpa ORtg DRtg Pace, absorb(fid Season) vce(cluster fid)

* Targets: 0.994 | 1.021 | 0.689 (ns) | 1.114 | 0.968 (se .148) | 0.977 | -0.061 (ns)

*------------------------------------------------------------------------------
* SECTION 10.  Cross-check against a method that does not use reghdfe.
*   areg and reg with explicit dummies are algebraically identical to reghdfe;
*   reghdfe is simply faster.  The coefficient must match to every decimal.
*------------------------------------------------------------------------------
areg WinRate tpa i.Season, absorb(fid) vce(cluster fid)
display as result "areg coefficient    = " %9.6f _b[tpa]

estimates restore c2
display as result "reghdfe coefficient = " %9.6f _b[tpa]

* These two numbers must be identical.

*------------------------------------------------------------------------------
* SECTION 11.  VERIFICATION SUMMARY
*   Run this last.  Compare the two columns.
*------------------------------------------------------------------------------
display _n as text "{hline 62}"
display as text "VERIFICATION" _col(38) "your value" _col(52) "target"
display as text "{hline 62}"

estimates restore c1
display as text "(1) 3PA%"            _col(38) %10.3f _b[tpa]    _col(52) "  0.892"
estimates restore c2
display as text "(2) 3PA%"            _col(38) %10.3f _b[tpa]    _col(52) "  0.968"
estimates restore c3
display as text "(3) 3PA%"            _col(38) %10.3f _b[tpa]    _col(52) "  1.336"
estimates restore c4
display as text "(4) 3PA%"            _col(38) %10.3f _b[tpa]    _col(52) " -1.015"
display as text "(4) 3PA% squared"    _col(38) %10.3f _b[tpa2]   _col(52) "  3.706"
display as text "(4) 3PA% x Year"     _col(38) %10.3f _b[tpa_y]  _col(52) " -0.144"
display as text "(4) 3PA% x Year sq"  _col(38) %10.4f _b[tpa_y2] _col(52) "-0.0075"
estimates restore c5
display as text "(5) 3PA%"            _col(38) %10.3f _b[tpa]    _col(52) " -0.393"
display as text "(5) ORtg"            _col(38) %10.3f _b[ORtg]   _col(52) "  0.030"
display as text "(5) DRtg"            _col(38) %10.3f _b[DRtg]   _col(52) " -0.030"

estimates restore c4
quietly test tpa_y tpa_y2
display as text "F: no time variation" _col(38) %10.2f r(F)      _col(52) "   1.62"
quietly test tpa2
display as text "F: no curvature"      _col(38) %10.2f r(F)      _col(52) "   1.66"
quietly test tpa tpa2 tpa_y tpa_y2
display as text "F: no effect at all"  _col(38) %10.2f r(F)      _col(52) "   8.35"
display as text "{hline 62}"
display as text "Every value in both columns should match exactly."

*------------------------------------------------------------------------------
* SECTION 12.  OPTIONAL. Reproduce Figure 1.
*   Skip this if anything above failed; it is not needed for the results.
*------------------------------------------------------------------------------
estimates restore c4
matrix b = e(b)
matrix V = e(V)
local ib  = colnumb(b, "tpa")
local ib2 = colnumb(b, "tpa2")
local ib3 = colnumb(b, "tpa_y")
local ib4 = colnumb(b, "tpa_y2")

local tc = invttail(e(df_r), 0.025)     // 2.045 with 29 clusters-1

tempname pf
tempfile mefile
postfile `pf' season me lo hi using "`mefile'", replace
quietly levelsof Season, local(yrs)
foreach y of local yrs {
    quietly summarize tpa if Season == `y', meanonly
    local xb  = r(mean)
    local ycv = `y' - 2014.5

    matrix g = J(1, colsof(b), 0)
    matrix g[1,`ib' ] = 1
    matrix g[1,`ib2'] = 2*`xb'
    matrix g[1,`ib3'] = `ycv'
    matrix g[1,`ib4'] = (`ycv')^2
    matrix mE = g*b'
    matrix mV = g*V*g'
    local me = mE[1,1]/100
    local se = sqrt(mV[1,1])/100

    post `pf' (`y') (`me') (`me'-`tc'*`se') (`me'+`tc'*`se')
}
postclose `pf'

preserve
use "`mefile'", clear
twoway (rarea lo hi season, color(navy%15) lwidth(none))          ///
       (line me season, lcolor(navy) lwidth(medthick)),           ///
       yline(0, lcolor(gs10))                                     ///
       xtitle("Season") ytitle("{&Delta} win rate per +1 pp in 3PA%") ///
       title("Marginal effect of three-point attempt rate on win rate") ///
       legend(off) graphregion(color(white))
graph export "Figure1_MarginalEffect.png", replace width(1800)
restore

*==============================================================================
* End of file.
*==============================================================================
