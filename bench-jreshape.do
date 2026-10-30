* bench-jreshape.do — runs one reshape method in one direction; called by run-benchmarks-jreshape.do
* Usage: do bench-jreshape.do <method> <direction>, where direction is long or wide
args method dir

* Reshaping long starts from wide data, and vice versa
if ("`dir'" == "long") use test_data_wide, clear
else                   use test_data_long, clear

if      ("`method'" == "baseline")    qui disp ""
else if ("`method'" == "reshape")     reshape  `dir' var, i(id) j(new)
else if ("`method'" == "greshape")    greshape `dir' var, i(id) j(new)
else if ("`method'" == "jreshape10")  jreshape `dir' var, i(id) j(new) nbatches(10)
else if ("`method'" == "jreshape100") jreshape `dir' var, i(id) j(new) nbatches(100)

* Reached only if everything above succeeded. Create a file that the parent
* process can check that it exists
tempname ok
file open `ok' using ok_jreshape_`dir'_`method'.txt, write replace
file close `ok'
