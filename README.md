# DFU Mode
Control + Option + Shift + Power (MacBook Air M1)

# Установка

1. Заходим в Safari и логинимся в GitHub
Входим в tailscale
sudo rm /etc/zshenv добовляем удаление подобного говна
3. Выполняем код ниже и закидываем ключ в поле

```bash
# первый вызов git предложит поставить CLT (или это сделает install.sh сам,
# headless-совместимо); Rosetta и сабмодули install.sh тоже ставит сам
read "key_path?Enter path to SSH private key: "
export GIT_SSH_COMMAND="ssh -i $key_path"
git clone git@github.com:CosmDandy/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

Приватные конфиги (ssh, rbw, env) едут сабмодулем `private/` — отдельный клон
`~/.dotfiles-private` больше не нужен. Интерактивная настройка приложений:
`platform/macos/install-extra.sh` (в headless-прогоне пропускается автоматически).

balena etcher
Office 2024
wispr flow
wakatime
телемост
remote desktop
meta
sound id reference
