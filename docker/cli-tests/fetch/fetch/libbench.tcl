# -*- tcl -*-

# Options:
# -interp <name>		Name of the interp running the benchmarks.
# -thread <num>                 Invoke threaded benchmarks, number of threads to use.
# -errors <boolean>             Throw errors, or not.

# Benchmark results are usually a time in microseconds, but the
# following special values can occur:
#
# - BAD_RES    - Result from benchmark body does not match expectations.
# - ERR        - Benchmark body aborted with an error.
# - Any string - Forced by error code 666 to pass to management.

#
# We claim all procedures starting with bench*
#
