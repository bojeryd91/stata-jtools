* bench-jcollapse.do — runs one collapse method; called by run-benchmarks-jcollapse.do
* Usage: do bench-jcollapse.do <method>
args method
use test_data_collapse, clear

* The same statistics for every method
local clist (mean) x* (sd) sd_x1=x1 (p50) p50_x1=x1 (count) n=x1

if      ("`method'" == "baseline")     qui disp ""
else if ("`method'" == "collapse")     collapse  `clist', by(g)
else if ("`method'" == "gcollapse")    gcollapse `clist', by(g)
else if ("`method'" == "jcollapse10")  jcollapse `clist', by(g) nbatches(10)
else if ("`method'" == "jcollapse100") jcollapse `clist', by(g) nbatches(100)
else error 198   // unknown method

* Reached only if everything above succeeded. Create a file that the parent
* process can check that it exists
tempname ok
file open `ok' using ok_jcollapse_`method'.txt, write replace
file close `ok'
