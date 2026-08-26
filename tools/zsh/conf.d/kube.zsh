# KUBECONFIG is assembled automatically from ~/.kube/configs/*.yaml, merged with ':'.
# Drop a cluster config in there and kubectl/k9s/kubectx see every context at once, with no
# manual export. Switching: kubectx for the context, kubens for the namespace.
() {
  local -a cfgs
  cfgs=(~/.kube/configs/*.yaml(N) ~/.kube/configs/*.yml(N))
  (( $#cfgs )) && export KUBECONFIG="${(j.:.)cfgs}"
}
