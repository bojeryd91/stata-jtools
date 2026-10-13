*! version 0.1.0  12oct2026  Jesper Böjeryd
*! Copyright (c) 2026 Jesper Böjeryd. MIT License.
*! Issues: https://github.com/bojeryd91/stata-jtools/issues
/*
	jjoinby: memory-efficient joinby for large datasets (part of stata-jtools)

	Forms all pairwise combinations of master and using observations within
	each value of the key variables, as joinby does, but in batches. The
	master data are sorted by the keys and split into batches that never split
	a key value; the using data are sorted and split into the same key ranges.
	Each pair of batches is joined with joinby, and the results are appended.
	This matters most when the output is much larger than the inputs.

	Syntax:
		jjoinby varlist using filename [, options]

	Unlike joinby, the key variables must be given explicitly.

	Options:
		nbatches(#)   split the master data into about # batches
		batchsize(#)  use master batches of about # observations
		fast          do not keep track of the original row order; on error,
		              the data are restored sorted by the keys
		Other joinby options (unmatched(), _merge(), update, replace, nolabel)
		are passed on to joinby for each batch.

	On error, the original data are restored.
	See README.md for details.
*/
program define jjoinby
	version 17.0
	syntax varlist using/, [NBatches(integer 1) BATCHSize(integer 0) fast *]

	* Record whether each key is string or numeric in master
	local keytypes
	foreach k of local varlist {
		capture confirm string variable `k'
		local keytypes `keytypes' `=cond(_rc, "num", "str")'
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
			bounds(`bounds') nbounds(`nbounds') saving(`using_sorted')
		local uedges `r(edges)'
		local nu = r(N)

		*** Join batch by batch
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
				if "`fast'" == "" drop `orig_order'   // not part of the join

				joinby `varlist' using `upart', `options'

				tempfile joined`ii'
				save `joined`ii'', emptyok
			}
		}
		qui {
			clear
			forval ii = 1/`nbatches' {
				append using `joined`ii''
			}
		}
	}
	local rc = _rc
	if `rc' { // If internal error occurs, reload the original data
		if `saved' qui use `all_data', clear
		if "`fast'" == "" {
			sort `orig_order'
			disp as error "jjoinby failed; original data restored"
		}
		else {
			disp as error "jjoinby failed; original data restored, sorted by `varlist'"
		}
		exit `rc'
	}
end
