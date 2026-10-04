*==============================================================================
* Three-Point Attempt Rate and Winning Outcomes: Evidence from the NBA (2005-2024)
* Haotian Chang
*
* Input : nba_advanced_stats.csv  (600 franchise-season observations)
* Output: table2.rtf, table3.rtf, table4_values.csv, figure1_marginal_effect_stata.png
*==============================================================================

clear all
set more off
eststo clear

*------------------------------------------------------------------------------
* PART 0. Load the data and build the variables
*------------------------------------------------------------------------------
* cd "C:\Users\m1861\Downloads"          // <- edit to your folder
import delimited "nba_advanced_stats.csv", clear varnames(1) case(preserve)

* The header "3PA%" is not a legal Stata name, so Stata renames it (PA or v7
* depending on the version). It is always the 7th column, so grab it there.
capture confirm variable tpa
if _rc {
    unab allv : _all
    local v3pa : word 7 of `allv'
    rename `v3pa' tpa
}
quietly summarize tpa
assert abs(r(min) - .105) < .001 & abs(r(max) - .519) < .001

encode FranchiseID, gen(fid)          // 30 franchises
encode Team,        gen(tid)          // 35 raw team names (robustness only)

gen double yc     = YearIndex - 10.5  // season counter, centered at the midpoint
gen double tpa2   = tpa^2
gen double tpa_y  = tpa*yc
gen double tpa_y2 = tpa*yc^2

* one 3PA% variable per season, for the unrestricted model
forvalues s = 2005/2024 {
    gen double tpa_`s' = tpa*(Season == `s')
}

label var WinRate "Win Rate"
label var tpa     "3PA%"
label var tpa2    "3PA% squared"
label var tpa_y   "3PA% x YearIndex"
label var tpa_y2  "3PA% x YearIndex squared"
label var ORtg    "Offensive Rating"
label var DRtg    "Defensive Rating"
label var Pace    "Pace"

*------------------------------------------------------------------------------
* A small helper: subtract each group's own average from a list of variables.
*   demean WinRate tpa, by(fid)
* replaces WinRate and tpa with their deviations from each team's mean.
*------------------------------------------------------------------------------
capture program drop demean
program define demean
    syntax varlist, by(varname)
    foreach v of local varlist {
        quietly recast double `v'
        tempvar m
        quietly bysort `by': egen double `m' = mean(`v')
        quietly replace `v' = `v' - `m'
        drop `m'
    }
end


*------------------------------------------------------------------------------
* PART 1. Table 2 -- summary statistics
*------------------------------------------------------------------------------

* Panel A
estpost summarize WinRate tpa ORtg DRtg Pace
esttab using table2.rtf, replace                                              ///
    cells("count(fmt(0)) mean(fmt(3 3 2 2 2)) sd(fmt(3 3 2 2 2)) min(fmt(3 3 2 2 2)) max(fmt(3 3 2 2 2))") ///
    collabels("Obs." "Mean" "Std. Dev." "Min" "Max")                          ///
    label nonumber nomtitle noobs                                             ///
    title("Table 2, Panel A. Summary statistics")

* Which team-season holds each minimum and maximum
display _n "Min / max holders"
foreach v in WinRate tpa ORtg DRtg Pace {
    sort `v'
    display "`v'" _col(12) "min: " FranchiseID[1] ", " Season[1] ///
            _col(34) "max: " FranchiseID[_N] ", " Season[_N]
}

* Panel B -- where does the variation come from?
display _n "Variable   Total SD   Between seasons   SD after 2-way FE   Absorbed by FE"
foreach v in WinRate tpa ORtg DRtg Pace {
    quietly summarize `v'
    local sd_tot  = r(sd)
    local var_tot = r(Var)

    * share of the variance that is just the season-to-season trend
    tempvar sm
    quietly bysort Season: egen double `sm' = mean(`v')
    quietly summarize `sm'
    local between = r(Var)/`var_tot'

    * what is left once team and season averages are removed
    quietly reg `v' i.fid i.Season
    tempvar e
    quietly predict double `e', resid
    quietly summarize `e'
    local sd_fe    = r(sd)
    local absorbed = 1 - r(Var)/`var_tot'

    display "`v'" _col(12) %7.3f `sd_tot' _col(27) %5.1f 100*`between' "%" ///
            _col(45) %7.3f `sd_fe' _col(64) %5.1f 100*`absorbed' "%"
    drop `sm' `e'
}


*------------------------------------------------------------------------------
* PART 2. Table 3 -- the five specifications
*------------------------------------------------------------------------------

* Two totals needed for the R-squared rows (full sample):
*   SST = total variation in win rate
*   SSW = variation left after removing team AND season averages
quietly summarize WinRate
scalar SST = r(Var)*(r(N) - 1)
tempvar mi mt ww
quietly bysort fid:    egen double `mi' = mean(WinRate)
quietly bysort Season: egen double `mt' = mean(WinRate)
quietly summarize WinRate
gen double `ww' = (WinRate - `mi' - `mt' + r(mean))^2
quietly summarize `ww'
scalar SSW = r(sum)
drop `mi' `mt' `ww'

* WHY WE DEMEAN: same model, two ways.
reg WinRate tpa i.fid i.Season, vce(cluster fid)
display as result "Plain reg with team dummies:  coef = " %8.6f _b[tpa] "   SE = " %8.6f _se[tpa]
preserve
    demean WinRate tpa, by(fid)
    quietly reg WinRate tpa i.Season, vce(cluster fid)
    display as result "Demeaned, then reg:           coef = " %8.6f _b[tpa] "   SE = " %8.6f _se[tpa]
restore
* Same coefficient. The second SE is the one in the paper.

* (1) Quadratic, no fixed effects -- ordinary reg on the raw data
reg WinRate tpa tpa2, vce(cluster fid)
estadd scalar r2_full   = e(r2)
estadd scalar r2_within = e(r2)
estadd local  teamfe   "No"
estadd local  seasonfe "No"
estadd local  controls "No"
eststo r1

* (2)-(5) and the unrestricted model: demean by team, keep season dummies
preserve
    demean WinRate tpa tpa2 tpa_y tpa_y2 ORtg DRtg Pace tpa_2005-tpa_2024, by(fid)

    * (2) Linear + FE  -- the headline result
    reg WinRate tpa i.Season, vce(cluster fid)
    estadd scalar r2_full   = 1 - e(rss)/scalar(SST)
    estadd scalar r2_within = 1 - e(rss)/scalar(SSW)
    estadd local  teamfe   "Yes"
    estadd local  seasonfe "Yes"
    estadd local  controls "No"
    eststo r2

    * (3) Quadratic + FE
    reg WinRate tpa tpa2 i.Season, vce(cluster fid)
    estadd scalar r2_full   = 1 - e(rss)/scalar(SST)
    estadd scalar r2_within = 1 - e(rss)/scalar(SSW)
    estadd local  teamfe   "Yes"
    estadd local  seasonfe "Yes"
    estadd local  controls "No"
    eststo r3

    * (4) Full quadratic-interaction + FE  -- the preferred specification
    reg WinRate tpa tpa2 tpa_y tpa_y2 i.Season, vce(cluster fid)
    estadd scalar r2_full   = 1 - e(rss)/scalar(SST)
    estadd scalar r2_within = 1 - e(rss)/scalar(SSW)
    estadd local  teamfe   "Yes"
    estadd local  seasonfe "Yes"
    estadd local  controls "No"
    eststo r4

    * (5) Full + FE + performance controls  -- the bad-control comparison
    reg WinRate tpa tpa2 tpa_y tpa_y2 ORtg DRtg Pace i.Season, vce(cluster fid)
    estadd scalar r2_full   = 1 - e(rss)/scalar(SST)
    estadd scalar r2_within = 1 - e(rss)/scalar(SSW)
    estadd local  teamfe   "Yes"
    estadd local  seasonfe "Yes"
    estadd local  controls "Yes"
    eststo r5

    * Unrestricted model: a separate 3PA% slope for every season (Table 4)
    reg WinRate tpa_2005-tpa_2024 i.Season, vce(cluster fid)
    eststo flex
restore

esttab r1 r2 r3 r4 r5 using table3.rtf, replace                               ///
    keep(tpa tpa2 tpa_y tpa_y2 ORtg DRtg Pace)                                ///
    order(tpa tpa2 tpa_y tpa_y2 ORtg DRtg Pace)                               ///
    b(3 3 3 4 4 4 4) se(3 3 3 4 4 4 4)                                        ///
    star(* 0.05 ** 0.01 *** 0.001) label                                      ///
    mtitles("Quadratic" "Linear + FE" "Quadratic + FE" "Full + FE"            ///
            "Full + FE + controls")                                           ///
    stats(teamfe seasonfe controls N r2_full r2_within,                       ///
          labels("Team Fixed Effects" "Season Fixed Effects"                  ///
                 "Performance controls" "Observations" "R-squared"            ///
                 "Within R-squared")                                          ///
          fmt(0 0 0 0 3 3))                                                   ///
    title("Table 3. Regression Results: Three-Point Attempt Rate and Win Rate") ///
    addnotes("Standard errors clustered by franchise (30 clusters) in parentheses.")

* also show it on screen
esttab r1 r2 r3 r4 r5, keep(tpa tpa2 tpa_y tpa_y2 ORtg DRtg Pace)            ///
    b(3 3 3 4 4 4 4) se(3 3 3 4 4 4 4) star(* 0.05 ** 0.01 *** 0.001)        ///
    stats(N r2_full r2_within, fmt(0 3 3)) label


*------------------------------------------------------------------------------
* PART 3. Joint hypothesis tests on column (4)
*   b3 = b4 = 0 is ONE joint hypothesis, so it needs an F test.
*------------------------------------------------------------------------------
estimates restore r4
test tpa_y tpa_y2                 // no time variation       paper: F = 1.62, p = .215
test tpa2                         // no curvature            paper: F = 1.66, p = .207
test tpa tpa2 tpa_y tpa_y2        // no effect at all        paper: F = 8.35, p = .0001

estimates restore flex
testparm tpa_2005-tpa_2024        // all 20 slopes zero      paper: F = 2.53, p = .011
quietly test tpa_2005 = tpa_2006
forvalues s = 2007/2023 {
    quietly test tpa_2005 = tpa_`s', accumulate
}
test tpa_2005 = tpa_2024, accumulate   // all 20 equal       paper: F = 0.97, p = .514


*------------------------------------------------------------------------------
* PART 4. Table 4 -- marginal effect by season
*   ME = b1 + 2*b2*(mean 3PA% that season) + b3*yc + b4*yc^2
*   lincom works after reg (it is reghdfe that it refuses).
*   Everything is divided by 100: the effect of a +1 percentage point change.
*------------------------------------------------------------------------------
* Results go into a matrix (not locals) so later parts can use them even
* if you run this file one part at a time.
matrix T4 = J(20, 12, .)
matrix colnames T4 = Season tpa me se lo hi p sl sse slo shi sp

estimates restore r4
local row = 0
forvalues y = 2005/2024 {
    local ++row
    quietly summarize tpa if Season == `y', meanonly
    local xb  = r(mean)
    local yc  = `y' - 2014.5
    local yc2 = (`y' - 2014.5)^2       // parentheses matter: -9.5^2 would be -90.25
    quietly lincom _b[tpa] + 2*`xb'*_b[tpa2] + (`yc')*_b[tpa_y] + `yc2'*_b[tpa_y2]
    matrix T4[`row', 1] = `y'
    matrix T4[`row', 2] = `xb'
    matrix T4[`row', 3] = r(estimate)/100
    matrix T4[`row', 4] = r(se)/100
    matrix T4[`row', 5] = r(lb)/100
    matrix T4[`row', 6] = r(ub)/100
    matrix T4[`row', 7] = r(p)
}

estimates restore flex
local tc = invttail(e(df_r), 0.025)     // t critical value, 29 df = 2.045
local row = 0
forvalues y = 2005/2024 {
    local ++row
    matrix T4[`row',  8] = _b[tpa_`y']/100
    matrix T4[`row',  9] = _se[tpa_`y']/100
    matrix T4[`row', 10] = (_b[tpa_`y'] - `tc'*_se[tpa_`y'])/100
    matrix T4[`row', 11] = (_b[tpa_`y'] + `tc'*_se[tpa_`y'])/100
    matrix T4[`row', 12] = 2*ttail(e(df_r), abs(_b[tpa_`y']/_se[tpa_`y']))
}

* print Table 4 with stars
display _n "Season  Mean3PA%       ME        SE          95% CI           Slope       SE"
forvalues r = 1/20 {
    local p1 = el(T4, `r', 7)
    local p2 = el(T4, `r', 12)
    local s1 = cond(`p1' < .001, "***", cond(`p1' < .01, "**", cond(`p1' < .05, "*", "")))
    local s2 = cond(`p2' < .001, "***", cond(`p2' < .01, "**", cond(`p2' < .05, "*", "")))
    display el(T4,`r',1) "   " %6.3f el(T4,`r',2) "   " %7.4f el(T4,`r',3) "`s1'" ///
            _col(32) "(" %6.4f el(T4,`r',4) ")  [" %7.4f el(T4,`r',5) ", "       ///
            %7.4f el(T4,`r',6) "]   " %7.4f el(T4,`r',8) "`s2'" _col(80)       ///
            "(" %6.4f el(T4,`r',9) ")"
}


*------------------------------------------------------------------------------
* PART 5. Robustness of the headline result (Section 4.3)
*   Each subsample is demeaned on its own, because team averages change when
*   seasons are dropped.
*------------------------------------------------------------------------------
preserve                                           // drop the two pandemic seasons
    keep if !inlist(Season, 2020, 2021)
    demean WinRate tpa, by(fid)
    reg WinRate tpa i.Season, vce(cluster fid)     // paper: 0.994
restore

preserve                                           // 2005-2019 only
    keep if Season <= 2019
    demean WinRate tpa, by(fid)
    reg WinRate tpa i.Season, vce(cluster fid)     // paper: 1.021
restore

preserve                                           // 2015-2024 only
    keep if Season >= 2015
    demean WinRate tpa, by(fid)
    reg WinRate tpa i.Season, vce(cluster fid)     // paper: 0.689, p = .103
restore

preserve                                           // add Pace
    demean WinRate tpa Pace, by(fid)
    reg WinRate tpa Pace i.Season, vce(cluster fid) // paper: 1.114
restore

* Heteroskedasticity-robust instead of clustered.
* Without clustering the team dummies DO count toward degrees of freedom,
* so here the plain dummy regression is the exact match.
reg WinRate tpa i.fid i.Season, vce(robust)         // paper: 0.968 (0.148)

* No fixed effects at all (README table)
reg WinRate tpa, vce(cluster fid)                   // 0.249 (0.103)

* 35 raw team names instead of 30 franchises.
* With raw names the panel is UNBALANCED (Seattle has 4 seasons, OKC 16, ...),
* so the season dummies must be demeaned too. In the balanced 30-franchise
* panel that step is unnecessary, which is why the code above skips it.
preserve
    tab Season, gen(D)
    demean WinRate tpa D2-D20, by(tid)
    reg WinRate tpa D2-D20, vce(cluster tid)        // paper: 0.977
restore

* The bad-control demonstration: add the mediators, the effect disappears
preserve
    demean WinRate tpa ORtg DRtg Pace, by(fid)
    reg WinRate tpa ORtg DRtg Pace i.Season, vce(cluster fid)   // paper: -0.061
restore


*------------------------------------------------------------------------------
* PART 6. Figure 1
*------------------------------------------------------------------------------
preserve
    clear
    svmat double T4, names(col)          // one row per season, from PART 4
    export delimited using "table4_values.csv", replace

    twoway (rarea lo hi Season, color("43 108 176%16") lwidth(none))           ///
           (line me Season, lcolor("43 108 176") lwidth(medthick))             ///
           (rcap slo shi Season, lcolor("192 86 33%80") lwidth(thin) msize(small)) ///
           (scatter sl Season, mcolor("192 86 33%80") msymbol(O) msize(small)), ///
        yline(0, lcolor(gs10) lwidth(thin))                                    ///
        xlabel(2005(2)2023) xscale(range(2004.3 2024.7))                      ///
        ylabel(-.02(.01).03, format(%4.2f) angle(0) grid glcolor(gs14))       ///
        xtitle("Season") ytitle("{&Delta} win rate per +1 pp in 3PA%")        ///
        title("Marginal effect of three-point attempt rate on win rate, 2005–2024", ///
              size(medium) color(black))                                     ///
        legend(order(1 "95% CI (quadratic-interaction)"                        ///
                     2 "Marginal effect, quadratic-interaction model"          ///
                     4 "Season-specific slope (unrestricted)")                 ///
               ring(0) position(7) cols(1) region(lstyle(none)) size(small))  ///
        graphregion(color(white)) plotregion(color(white) lstyle(none))       ///
        xsize(9) ysize(5.2)
    graph export "figure1_marginal_effect_stata.png", replace width(1800)
restore


*------------------------------------------------------------------------------
* PART 7. Verification -- every value should equal the paper
*------------------------------------------------------------------------------
display _n as text "{hline 64}"
display as text "CHECK" _col(40) "yours" _col(54) "paper"
display as text "{hline 64}"
estimates restore r1
display as text "(1) 3PA%  coef / SE"   _col(36) %7.3f _b[tpa] %7.3f _se[tpa] _col(54) "0.892 0.626"
estimates restore r2
display as text "(2) 3PA%  coef / SE"   _col(36) %7.3f _b[tpa] %7.3f _se[tpa] _col(54) "0.968 0.237"
display as text "(2) within R-squared"  _col(40) %7.3f e(r2_within)            _col(54) "0.070"
estimates restore r3
display as text "(3) 3PA%  coef / SE"   _col(36) %7.3f _b[tpa] %7.3f _se[tpa] _col(54) "1.336 0.615"
estimates restore r4
display as text "(4) 3PA%  coef / SE"   _col(36) %7.3f _b[tpa] %7.3f _se[tpa] _col(54) "-1.015 1.762"
display as text "(4) x Year sq coef/SE" _col(34) %8.4f _b[tpa_y2] %8.4f _se[tpa_y2] _col(54) "-0.0075 0.0058"
quietly test tpa_y tpa_y2
display as text "F: no time variation"  _col(40) %7.2f r(F)                    _col(54) "1.62"
quietly test tpa tpa2 tpa_y tpa_y2
display as text "F: no effect at all"   _col(40) %7.2f r(F)                    _col(54) "8.35"
estimates restore r5
display as text "(5) 3PA%  coef / SE"   _col(36) %7.3f _b[tpa] %7.3f _se[tpa] _col(54) "-0.393 0.427"
display as text "ME 2005 / 2024"        _col(34) %8.4f el(T4,1,3) %8.4f el(T4,20,3) _col(54) "0.0113 -0.0013"
display as text "Flex 2005 slope / SE"  _col(34) %8.4f el(T4,1,8) %8.4f el(T4,1,9) _col(54) "0.0106 0.0052"
display as text "{hline 64}"

*==============================================================================
* End of file.
*==============================================================================
