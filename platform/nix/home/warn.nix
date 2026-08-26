# Shared warning accumulator for the activation hooks.
#
# The hooks deliberately do not fail activation when offline — otherwise an image build or
# a devpod up would break on any network hiccup. But that makes a failed install look like
# a successful one: a lone "warn:" drowns in hundreds of lines. So every warning is
# appended to a file and reportWarnings prints the summary as the last step.
#
# NOTE: a separate file rather than part of hooks.nix because darwin.nix declares hooks
# too. While it wrote warnings with a bare echo, a failing applyOrbstack reached neither
# the file nor the summary, and the activation reported success with a broken step.
{ config }:
rec {
  file = "${config.home.homeDirectory}/.cache/home-manager-warnings";
  mk = msg: ''{ echo "warn: ${msg}"; echo "${msg}" >> "${file}"; }'';
}
