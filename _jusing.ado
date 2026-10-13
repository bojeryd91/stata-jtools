*! version 0.1.0  12oct2026  Jesper Böjeryd
*! Copyright (c) 2026 Jesper Böjeryd. MIT License.
*! Issues: https://github.com/bojeryd91/stata-jtools/issues
/*
	_jusing: internal helper for jmerge and jjoinby (part of stata-jtools)

	Loads the using dataset, sorts it by the key variables, and splits it into
	the same key ranges as the batches of the master data. The master batches
	are described by bounds(): a dataset holding the key values of the first
	row of master batches 2, 3, ..., B. Using rows with keys below the first
	boundary go to batch 1, rows between boundary k-1 and k go to batch k, and
	rows at or above the last boundary go to batch B. Every using row thus
	lands in exactly one batch, and in the same batch as any master rows with
	the same keys.

	Syntax:
		_jusing using filename, keys(varlist) bounds(filename) nbounds(#)
		        saving(filename) [keytypes(str|num ...) vars(varlist) unique]

	keytypes() lists, for each key, whether it is string (str) or numeric
	(num) in the master data, to give a clear error if the types differ.
	vars() loads only these variables (keys must be included).
	unique requires the keys to identify the using observations uniquely.

	Stored results:
		r(edges)  first row of each batch in the saved using data, plus _N+1
		          as a sentinel; batch b covers rows word(b) to word(b+1) - 1,
		          which is empty when the two are equal
		r(N)      number of observations in the using data

	Replaces the data in memory with the sorted using data and saves it to
	saving().
*/
program define _jusing, rclass
	version 17.0
	syntax using/, keys(string) bounds(string) nbounds(integer) ///
		saving(string) [keytypes(string) vars(string) unique]

	* Load the using data (only the variables needed, if specified)
	if "`vars'" != "" use `vars' using `"`using'"', clear
	else              use `"`using'"', clear

	* Keys must exist in the using data and have the same type as in master
	local k_i = 0
	foreach k of local keys {
		local ++k_i
		capture confirm variable `k', exact
		if _rc {
			disp as error "variable `k' not found in using data"
			exit 111
		}
		capture confirm string variable `k'
		local is = cond(_rc, "num", "str")
		local want : word `k_i' of `keytypes'
		if "`want'" != "" & "`want'" != "`is'" {
			local mtype = cond("`want'" == "str", "string", "numeric")
			local utype = cond("`is'"   == "str", "string", "numeric")
			disp as error "key variable `k' is `mtype' in master but `utype' in using data"
			exit 106
		}
	}
	local nu = _N

	* Add the master boundary keys as marker rows (rank 0), sorted before
	* using rows (rank 1) with the same keys
	tempvar rank
	qui gen byte `rank' = 1
	qui append using `"`bounds'"', nolabel nonotes
	qui replace `rank' = 0 if missing(`rank')
	sort `keys' `rank'

	* Check uniqueness of the keys among the using rows
	if "`unique'" != "" {
		capture by `keys' `rank': assert _N == 1
		if _rc {
			disp as error "variable(s) `keys' do not uniquely identify observations in the using data"
			exit 459
		}
	}

	* Batch k+1 starts right after marker k: at row p_k - k + 1 once the
	* k markers up to and including marker k are dropped
	local starts
	if `nbounds' > 0 {
		mata: st_local("starts", invtokens(strofreal(( ///
			selectindex(st_data(., "`rank'") :== 0) - (1::`nbounds') :+ 1)', "%15.0f")))
	}
	qui drop if `rank' == 0
	drop `rank'

	qui save `"`saving'"', replace emptyok

	return local  edges "1 `starts' `=`nu' + 1'"
	return scalar N = `nu'
end
