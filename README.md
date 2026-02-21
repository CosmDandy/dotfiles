# DFU Mode
Control + Option + Shift + Power (MacBook Air M1)

# Установка

1. Заходим в Safari и логинимся в GitHub
Входим в tailscale
sudo rm /etc/zshenv добовляем удаление подобного говна
3. Выполняем код ниже и закидываем ключ в поле
```bash
xcode-select --install
softwareupdate --install-rosetta --agree-to-license
read "key_path?Enter path to SSH private key: "
GIT_SSH_COMMAND="ssh -i $key_path" git clone -b macos git@github.com:CosmDandy/dotfiles.git .dotfiles
GIT_SSH_COMMAND="ssh -i $key_path" git clone git@github.com:CosmDandy/dotfiles-private.git .dotfiles-private
cd ~/.dotfiles
./setup.sh
```

balena etcher
Office 2024
wispr flow
wakatime
телемост
remote desktop
meta
sound id reference
