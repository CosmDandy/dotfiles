# Kubernetes: KUBECONFIG автоматически собирается из ~/.kube/configs/*.yaml (мердж
# контекстов через ':'). Кладёшь конфиг кластера в ~/.kube/configs/<name>.yaml —
# kubectl/k9s/kubectx сразу видят все контексты, ручной export не нужен.
# Переключение: kubectx (контекст) / kubens (namespace); с fzf — интерактивный выбор.
() {
  local -a cfgs
  cfgs=(~/.kube/configs/*.yaml(N) ~/.kube/configs/*.yml(N))
  (( $#cfgs )) && export KUBECONFIG="${(j.:.)cfgs}"
}
