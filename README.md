```bash
xcode-select --install
softwareupdate --install-rosetta --agree-to-license
read "key_path?Enter path to SSH key: "
GIT_SSH_COMMAND="ssh -i $key_path" git clone -b macos git@github.com:CosmDandy/dotfiles.git .dotfiles
GIT_SSH_COMMAND="ssh -i $key_path" git clone git@github.com:CosmDandy/dotfiles-private.git .dotfiles-private
cd ~/.dotfiles
./setup.sh
```

# Шаблон для проектов с DevPod

Этот репозиторий является отправной точкой для всех моих проектов при работе с которыми я использую [DevPod](https://devpod.sh/)

Для создания проекта в DevPod я использую следующую команду:
```bash
devpod up . --id . --provider . --dotfiles https://github.com/CosmDandy/dotfiles-devpod.git
```

добавить сюда как входить в dfu mode
