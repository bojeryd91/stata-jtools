* test-jreshape.do — checks jreshape against reshape
* Run from the repository folder. Each cf stops with an error on any difference,
* and each rcof stops if a command does not fail with the expected code.
clear all
discard
set seed 20261030

*** Test data

* Wide: 20,000 ids in random order; stubs x (with missing values) and y;
* a string and a numeric variable that are constant within id
set obs 20000
gen long id = _n
gen str8 name = "id" + string(id)
gen byte grp = mod(id, 7)
forval k = 1/5 {
	gen x`k' = rnormal()
	gen y`k' = runiformint(1, 100)
}
replace x3 = . in 1/500
gen double u = runiform()
sort u
drop u
tempfile wide
save `wide'

* Long: the same data reshaped long, shuffled, without reshape's stored settings
reshape long x y, i(id) j(t)
gen double u = runiform()
sort u
drop u
local chars : char _dta[]
foreach c of local chars {
	if substr("`c'", 1, 3) == "ReS" char _dta[`c']
}
tempfile long
save `long'

* Wide with a string j: stubs xa, xb, xc
use `wide', clear
keep id name x1 x2 x3
rename (x1 x2 x3) (xa xb xc)
tempfile wides
save `wides'

* Long with a string j, shuffled, without stored settings
reshape long x, i(id) j(s) string
gen double u = runiform()
sort u
drop u
local chars : char _dta[]
foreach c of local chars {
	if substr("`c'", 1, 3) == "ReS" char _dta[`c']
}
tempfile longs
save `longs'

tempfile ref

*** Compare with reshape, with and without gtools and for several batch sizes
foreach opt in "" "nogtools" {
	foreach b in "nbatches(1)" "nbatches(7)" "batchsize(999)" {
		local label `b' `opt'

		* long, numeric j
		use `wide', clear
		reshape long x y, i(id) j(t)
		sort id t
		qui save `ref', replace
		use `wide', clear
		jreshape long x y, i(id) j(t) `b' `opt'
		sort id t
		cf _all using `ref'

		* wide, numeric j
		use `long', clear
		reshape wide x y, i(id) j(t)
		sort id
		qui save `ref', replace
		use `long', clear
		jreshape wide x y, i(id) j(t) `b' `opt'
		sort id
		cf _all using `ref'

		* long, string j
		use `wides', clear
		reshape long x, i(id) j(s) string
		sort id s
		qui save `ref', replace
		use `wides', clear
		jreshape long x, i(id) j(s) string `b' `opt'
		sort id s
		cf _all using `ref'

		* wide, string j
		use `longs', clear
		reshape wide x, i(id) j(s) string
		sort id
		qui save `ref', replace
		use `longs', clear
		jreshape wide x, i(id) j(s) string `b' `opt'
		sort id
		cf _all using `ref'

		* two i() variables
		use `wide', clear
		reshape long x y, i(grp id) j(t)
		sort grp id t
		qui save `ref', replace
		use `wide', clear
		jreshape long x y, i(grp id) j(t) `b' `opt'
		sort grp id t
		cf _all using `ref'

		disp as result "passed: `label'"
	}
}

*** by()/keys() syntax gives the same result as i()/j()
use `long', clear
reshape wide x y, i(id) j(t)
sort id
qui save `ref', replace
use `long', clear
jreshape wide x y, by(id) keys(t) nbatches(7)
sort id
cf _all using `ref'
disp as result "passed: by()/keys() syntax"

*** Invalid options: error 198, data left untouched
use `wide', clear
rcof "noisily jreshape long x y, i(id) j(t) keys(t)"                 == 198
rcof "noisily jreshape long x y, by(id) j(t)"                        == 198
rcof "noisily jreshape long x y, i(id)"                              == 198
rcof "noisily jreshape long x y, i(id) j(t) nbatches(2) batchsize(9)" == 198
rcof "noisily jreshape long x y, i(id) j(t) nbatches(0)"             == 198
rcof "noisily jreshape sideways x y, i(id) j(t)"                     == 198
cf _all using `wide'
disp as result "passed: invalid options"

*** A reshape that fails inside a batch: the data must come back unchanged
* noise varies within id, so reshape wide fails (nogtools: built-in reshape
* is certain to stop with an error here; greshape may handle it differently)
use `long', clear
gen double noise = rnormal()
tempfile bad
save `bad'
rcof "noisily jreshape wide x y, i(id) j(t) nbatches(5) nogtools" != 0
cf _all using `bad'                          // same rows, same order
disp as result "passed: original data and order restored after an error"

* With fast, the data come back sorted by i() instead
sort id t
tempfile bad_sorted
save `bad_sorted'
use `bad', clear
rcof "noisily jreshape wide x y, i(id) j(t) nbatches(5) nogtools fast" != 0
sort id t
cf _all using `bad_sorted'
disp as result "passed: original data restored after an error with fast"

disp _n as result "All jreshape tests passed"
