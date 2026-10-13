*! version 0.1.0  12oct2026  Jesper Böjeryd
*! Copyright (c) 2026 Jesper Böjeryd. MIT License.
*! Issues: https://github.com/bojeryd91/stata-jtools/issues
/*
	jmerge: memory-efficient merge for large datasets (part of stata-jtools)

	Merges in batches so that the working memory needed by merge scales with
	the batch rather than the full datasets. The master data are sorted by the
	key variables and split into batches that never split a key value. The
	using data are sorted and split into the same key ranges, so matching
	rows always meet in the same batch, and unmatched using rows are kept
	exactly once. Each pair of batches is merged with merge, and the results
	are appended.

	Syntax:
		jmerge 1:1 varlist using filename [, options]
		jmerge m:1 varlist using filename [, options]
		jmerge 1:m varlist using filename [, options]

	m:m merges are not allowed; use joinby or jjoinby instead.

	Before merging, jmerge checks that the keys uniquely identify the
	observations in the master data (1:1, 1:m) and in the using data (1:1, m:1).

	Options:
		keepusing(varlist)   variables to keep from the using data; only these
		                     (and the keys) are loaded
		generate(newvar)     name of the merge result variable (default _merge)
		nogenerate           do not create the merge result variable
		noreport             do not display the summary table
		nbatches(#)          split the master data into about # batches
		batchsize(#)         use master batches of about # observations
		fast                 do not keep track of the original row order; on
		                     error, the data are restored sorted by the keys
		Other merge options (keep(), assert(), update, replace, nolabel,
		nonotes, force) are passed on to merge for each batch.

	The result is sorted by the key variables.
	On error, the original data are restored.
	See README.md for details.
*/
program define jmerge
	version 17.0

	* Merge type
	gettoken mtype 0 : 0, parse(" ,")
	if "`mtype'" == "m:m" {
		disp as error "jmerge does not allow m:m merges"
		disp as error "{p 4 4 2}An m:m merge pairs observations within each key " ///
			"value by their order in the data, which is rarely meaningful. To " ///
			"form all pairwise combinations of master and using observations " ///
			"within each key value, use {bf:joinby} or {bf:jjoinby} instead.{p_end}"
		exit 198
	}
	if !inlist("`mtype'", "1:1", "m:1", "1:m") {
		disp as error "specify the merge type as 1:1, m:1 or 1:m, " ///
			"as in {bf:jmerge 1:1 id using filename}"
		exit 198
	}

	syntax varlist using/, [KEEPUSing(string) GENerate(name) NOGENerate ///
		NOREPort NBatches(integer 1) BATCHSize(integer 0) fast *]
	// NO in capitals: the macros are nogenerate and noreport

	* Name of the merge result variable
	if "`nogenerate'" != "" & "`generate'" != "" {
		disp as error "options generate() and nogenerate may not be combined"
		exit 198
	}
	if "`nogenerate'" != "" {
		tempvar mvar           // still needed for the report; dropped at the end
		local mname _merge
	}
	else {
		local mvar = cond("`generate'" == "", "_merge", "`generate'")
		local mname `mvar'
		capture confirm new variable `mvar'
		if _rc {
			disp as error "variable `mvar' already defined"
			exit 110
		}
	}

	* Which side must have unique keys
	local master_unique = inlist("`mtype'", "1:1", "1:m")
	local using_unique  = cond(inlist("`mtype'", "1:1", "m:1"), "unique", "")

	* Record whether each key is string or numeric in master
	local keytypes
	foreach k of local varlist {
		capture confirm string variable `k'
		local keytypes `keytypes' `=cond(_rc, "num", "str")'
	}

	* Variables to load from the using data
	local uvars
	if "`keepusing'" != "" {
		local uvars : list varlist | keepusing
		local kuopt keepusing(`keepusing')
	}

	* Unless fast, record the original row order, to restore it on error
	if "`fast'" == "" {
		tempvar orig_order
		qui gen long `orig_order' = _n
	}

	tempfile all_data bounds using_sorted upart
	local saved 0
	capture noi { // Do capture in case of internal error

		* Sort master by the keys and assign rows to batches
		_jbatches `varlist', nbatches(`nbatches') batchsize(`batchsize')
		local medges   `r(edges)'
		local nbatches = r(nbatches)

		* Master must have unique keys for 1:1 and 1:m
		if `master_unique' {
			capture by `varlist': assert _N == 1
			if _rc {
				disp as error "variable(s) `varlist' do not uniquely identify observations in the master data"
				exit 459
			}
		}

		*** Save master data to read from
		qui save `all_data'
		local saved 1

		* Key values of the first row of master batches 2, ..., B
		tempvar isbound
		qui {
			keep `varlist'
			gen byte `isbound' = 0
			forval ii = 2/`nbatches' {
				local r : word `ii' of `medges'
				replace `isbound' = 1 in `r'
			}
			keep if `isbound'
			drop `isbound'
			save `bounds', emptyok
		}
		local nbounds = _N

		* Sort the using data and split it into the same key ranges
		_jusing using `"`using'"', keys(`varlist') keytypes(`keytypes') ///
			bounds(`bounds') nbounds(`nbounds') saving(`using_sorted') ///
			vars(`uvars') `using_unique'
		local uedges `r(edges)'
		local nu = r(N)

		*** Merge batch by batch
		forval ii = 1/`nbatches' {
			local m_first : word   `ii'    of `medges'
			local m_last  : word `=`ii'+1' of `medges'
			local --m_last
			local u_first : word   `ii'    of `uedges'
			local u_last  : word `=`ii'+1' of `uedges'
			local --u_last
			qui {
				* Using rows in this key range (possibly none)
				if `u_first' <= `u_last' {
					use in `u_first'/`u_last' using `using_sorted', clear
				}
				else if `nu' == 0 {
					use `using_sorted', clear
				}
				else {               // empty, but with the using variables
					use in 1 using `using_sorted', clear
					drop in 1
				}
				save `upart', replace emptyok

				* Master rows in this batch
				use in `m_first'/`m_last' using `all_data', clear
				if "`fast'" == "" drop `orig_order'   // not part of the merge

				merge `mtype' `varlist' using `upart', generate(`mvar') ///
					`kuopt' `options'

				tempfile merged`ii'
				save `merged`ii'', emptyok
			}
		}
		qui {
			clear
			forval ii = 1/`nbatches' {
				append using `merged`ii''
			}
			sort `varlist'
		}
	}
	local rc = _rc
	if `rc' { // If internal error occurs, reload the original data
		if `saved' qui use `all_data', clear
		if "`fast'" == "" {
			sort `orig_order'
			disp as error "jmerge failed; original data restored"
		}
		else {
			disp as error "jmerge failed; original data restored, sorted by `varlist'"
		}
		exit `rc'
	}

	* Summary table, as displayed by merge
	if "`noreport'" == "" {
		forval v = 1/5 {
			qui count if `mvar' == `v'
			local n`v' = r(N)
		}
		local nm = `n1' + `n2'
		disp _n as text _col(5) "Result" _col(33) "Number of obs"
		disp as text _col(5) "{hline 41}"
		disp as text _col(5) "Not matched" _col(30) as result %16.0fc `nm'
		if `nm' > 0 {
			disp as text _col(9) "from master" _col(30) as result %16.0fc `n1' ///
				as text "  (`mname'==1)"
			disp as text _col(9) "from using"  _col(30) as result %16.0fc `n2' ///
				as text "  (`mname'==2)"
		}
		disp ""
		disp as text _col(5) "Matched" _col(30) as result %16.0fc `n3' ///
			as text "  (`mname'==3)"
		if `n4' + `n5' > 0 {
			disp as text _col(9) "missing updated"     _col(30) as result %16.0fc `n4' ///
				as text "  (`mname'==4)"
			disp as text _col(9) "nonmissing conflict" _col(30) as result %16.0fc `n5' ///
				as text "  (`mname'==5)"
		}
		disp as text _col(5) "{hline 41}"
	}
end
