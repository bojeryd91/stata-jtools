* test-jmerge.do — checks jmerge and jjoinby against merge and joinby
* Run from the repository folder. Each cf stops with an error on any difference.
clear all
discard
set seed 20261012

*** Test data
* 1:1 master: ids 1..100,000 in random order
set obs 100000
gen long id = _n
gen x = rnormal()
gen u = runiform()
sort u
drop u
tempfile m11
save `m11'

* 1:1 using: ids 50,001..150,000, so the first half of the master batches
* have no using rows, and the last batch also gets all using-only ids
clear
set obs 100000
gen long id = _n + 50000
gen y = rnormal()
tempfile u11
save `u11'

* Many rows per group: 200,000 rows in groups 1..20,000, random order
clear
set obs 200000
gen long g = runiformint(1, 20000)
gen x = rnormal()
gen str6 gs = "g" + string(g)                // string version of the key
tempfile many
save `many'

* One row per group: groups 1..30,000 (10,000 have no match in many)
clear
set obs 30000
gen long g = _n
gen y = rnormal()
gen str6 gs = "g" + string(g)
tempfile one
save `one'

*** 1:1
use `m11', clear
merge 1:1 id using `u11'
sort id
tempfile ref
save `ref', replace

use `m11', clear
jmerge 1:1 id using `u11', nbatches(10)
cf _all using `ref', all
disp as result "1:1 passed"

*** m:1, numeric key
use `many', clear
merge m:1 g using `one'
sort g x
save `ref', replace

use `many', clear
jmerge m:1 g using `one', nbatches(10)
sort g x
cf _all using `ref', all
disp as result "m:1 passed"

*** m:1, string key, keepusing(), keep(match), nogenerate
use `many', clear
merge m:1 gs using `one', keepusing(y) keep(match) nogenerate
sort gs x
save `ref', replace

use `many', clear
jmerge m:1 gs using `one', keepusing(y) keep(match) nogenerate nbatches(7)
sort gs x
cf _all using `ref', all
disp as result "m:1 with string key and options passed"

*** 1:m
use `one', clear
merge 1:m g using `many'
sort g x
save `ref', replace

use `one', clear
jmerge 1:m g using `many', batchsize(1000)
sort g x
cf _all using `ref', all
disp as result "1:m passed"

*** Errors, and the data restored in their original order afterwards
use `many', clear
rcof "noisily jmerge 1:1 g using `one'" == 459     // master keys not unique
cf _all using `many', all

use `one', clear
rcof "noisily jmerge m:1 g using `many'" == 459    // using keys not unique
cf _all using `one', all

rcof "noisily jmerge m:m g using `many'" == 198    // m:m not allowed
rcof "noisily jmerge 1:1 gs using `u11'" == 111    // key missing in using
disp as result "error checks passed"

*** jjoinby
* Master groups 1..20,000; using groups 10,001..25,000 with several rows each
clear
set obs 60000
gen long g = runiformint(10001, 25000)
gen z = rnormal()
tempfile jusing
save `jusing'

use `many', clear
keep g x
joinby g using `jusing'
sort g x z
save `ref', replace

use `many', clear
keep g x
jjoinby g using `jusing', nbatches(10)
sort g x z
cf _all using `ref', all
disp as result "jjoinby passed"

use `many', clear
keep g x
joinby g using `jusing', unmatched(both)
sort g x z _merge
save `ref', replace

use `many', clear
keep g x
jjoinby g using `jusing', unmatched(both) nbatches(10)
sort g x z _merge
cf _all using `ref', all
disp as result "jjoinby with unmatched(both) passed"
