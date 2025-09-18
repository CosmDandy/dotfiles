devpod context set-options --option DOTFILES_URL=git@github.com:CosmDandy/dotfiles-devpod.git --option GIT_SSH_SIGNATURE_FORWARDING=true --option SSH_ADD_PRIVATE_KEYS=true --option SSH_AGENT_FORWARDING=true --option SSH_INJECT_DOCKER_CREDENTIALS=true --option SSH_INJECT_GIT_CREDENTIALS=true
# Необходимо добавить указания .files конкретного

devpod provider add docker --name local-docker --use
devpod provider add ssh --name dev-ssh -o HOST=dev
devpod provider use local-docker
devpod provider list

devpod ide use cursor
