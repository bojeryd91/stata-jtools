*! version 0.2.0  30oct2026  Jesper Böjeryd
*! Copyright (c) 2026 Jesper Böjeryd. MIT License.
*! Issues: https://github.com/bojeryd91/stata-jtools/issues
/*
	_jbatches: internal helper for the stata-jtools commands

	Sorts the data in memory by the group variables and splits the rows into
	batches of about batchsize() rows each, without splitting any group across
	two batches. Each group goes into the batch where its first row falls.

	The batch boundaries are found in Mata through views of the key
	variables, so the only extra memory added is what sort itself needs. For
	each target boundary (row batchsize+1, 2*batchsize+1, ...), Mata scans
	forward to the first row that starts a new group, which costs about one
	group length per batch rather than a pass over all rows.

	Syntax:
		_jbatches varlist [, nbatches(#) batchsize(#)]

	Stored results:
		r(edges)      first row of each batch, plus _N+1 as a sentinel, so
		              batch b covers rows word(b) to word(b+1) - 1
		r(nbatches)   number of batches actually created (can be fewer than
		              nbatches(), because groups are kept whole)
		r(batchsize)  target batch size in rows

	Side effect: the data are left sorted by varlist.
*/
program define _jbatches, rclass
	version 17.0
	syntax varlist, [NBatches(integer 1) BATCHSize(integer 0)]

	* Check batch options
	if `nbatches' != 1 & `batchsize' != 0 {
		disp as error "You cannot specify both nbatches() and batchsize()"
		exit 198
	}
	if `nbatches' < 1 | `batchsize' < 0 {
		disp as error "nbatches() and batchsize() must be positive"
		exit 198
	}
	if _N == 0 {
		disp as error "no observations"
		exit 2000
	}

	* Target batch size in rows
	if `batchsize' == 0 local batchsize = ceil(_N/`nbatches')

	* Sort by group
	sort `varlist'

	* Split the keys into numeric and string variables (Mata views differ)
	local numvars
	local strvars
	foreach v of local varlist {
		capture confirm string variable `v'
		if _rc local numvars `numvars' `v'
		else   local strvars `strvars' `v'
	}

	* First row of each batch, plus a sentinel one past the end
	mata: st_local("edges", invtokens(strofreal( ///
		_jbatches_edges("`numvars'", "`strvars'", `batchsize'), "%15.0f")))
	local nb : word count `edges'
	local --nb

	return local  edges     "`edges'"
	return scalar nbatches  = `nb'
	return scalar batchsize = `batchsize'
end

* Mata function used above; dropped first so that reloading this file works
version 17.0
capture mata: mata drop _jbatches_edges()
mata:
// Batch boundaries for data sorted by the key variables. Returns the first
// row of each batch followed by N+1. A group starting at row r belongs to
// batch ceil(r/bs), so batch b starts at the first group start at or after
// row (b-1)*bs + 1.
real rowvector _jbatches_edges(string scalar numvars,
                               string scalar strvars,
                                 real scalar bs)
{
	real scalar    N, t, r, hasnum, hasstr
	real matrix    X
	string matrix  S
	real rowvector edges

	N      = st_nobs()
	hasnum = (numvars != "")
	hasstr = (strvars != "")
	if (hasnum) st_view( X, ., tokens(numvars))
	if (hasstr) st_sview(S, ., tokens(strvars))

	edges = 1
	t = bs + 1                      // first row of the next target batch
	while (t <= N) {
		// Scan forward from t to the first row that starts a new group
		r = t
		while (r <= N) {
			if (hasnum) {
				if (X[r, .] != X[r-1, .]) break
			}
			if (hasstr) {
				if (S[r, .] != S[r-1, .]) break
			}
			r++
		}
		if (r > N) break            // the last group runs to the end
		edges = edges, r
		t = (floor((r-1)/bs) + 1)*bs + 1   // next target after row r
	}
	return(edges, N + 1)
}
end
