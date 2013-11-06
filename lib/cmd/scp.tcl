# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. Helper commands for SCP transfer.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require tar 0.8 ; # GNU @LongName support in reader (untar).

debug level  cmd/scp
debug prefix cmd/scp {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export scp
    namespace ensemble create
}
namespace eval ::stackato::cmd::scp {
    namespace export \
	xfer_receive xfer_receive1 \
	xfer_transmit xfer_transmit1
    namespace ensemble create
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::scp::xfer_receive {config} {
    debug.cmd/scp {}

    set dst [$config @dst]

    fconfigure stdin -encoding binary -translation binary
    #file mkdir            $dst
    tar::untar stdin -dir $dst -chan
    return
}

proc ::stackato::cmd::scp::xfer_receive1 {config} {
    debug.cmd/scp {}

    set dst [$config @dst]

    file mkdir [file dirname $dst]
    set c [open $dst w]

    fconfigure stdin -encoding binary -translation binary
    fconfigure $c    -encoding binary -translation binary

    fcopy stdin $c
    close $c
    close stdin
    return
}

proc ::stackato::cmd::scp::xfer_transmit {config} {
    debug.cmd/scp {}

    set args [$config @src]

    fconfigure  stdout -encoding binary -translation binary
    tar::create stdout $args -chan
    close stdout
    return
}

proc ::stackato::cmd::scp::xfer_transmit1 {config} {
    debug.cmd/scp {}

    set src [$config @src]
    set c   [open $src r]

    fconfigure stdout -encoding binary -translation binary
    fconfigure $c     -encoding binary -translation binary

    fcopy $c stdout
    close $c
    close stdout
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::scp 0

