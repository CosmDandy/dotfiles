# Шаблон для проектов с DevPod

Этот репозиторий является отправной точкой для всех моих проектов при работе с которыми я использую [DevPod](https://devpod.sh/)

Для создания проекта в DevPod я использую следующую команду:
```bash
devpod up . --id . --provider . --dotfiles https://github.com/CosmDandy/dotfiles-devpod.git
```

```bash
cd ~/dotfiles; cp git/.gitconfig /tmp/ 2>/dev/null; git checkout -- . && git pull && mv /tmp/.gitconfig git/ 2>/dev/null
```
