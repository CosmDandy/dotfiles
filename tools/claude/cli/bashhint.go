package main

// Port of tools/claude/hooks/posttooluse-bashhint.sh: recognise a familiar
// trap from the error text and hand over the way out.
//
// The point is not blocking — the command has already run. The point is
// that a rule from CLAUDE.md ("macOS is BSD userland under zsh") is lost in
// the volume of that file and only gets remembered afterwards. Here it
// arrives exactly when it broke, with the replacement rather than the
// general principle.
//
// Every entry comes from mining actual transcripts, not from imagination.
// Hints stay in Russian: this is data addressed to the user's own model
// session, ported byte-for-byte from the shell script, not new product text.

import (
	"encoding/json"
	"io"
	"os"
	"regexp"
	"strings"
)

// pushWithoutPR matches `git … push`, allowing -C/-c and other flags to
// carry their own argument between "git" and "push" — so `git -C dir push`
// and `git --no-pager push` are still recognised as a push, not just a bare
// `git push`.
//
// NOTE: no (?m) here — the original is `grep -Eq pattern <<<"$cmd"`, which
// never lets a match span two physical lines. A [[:space:]] class matches a
// literal newline too, so (?m) alone would let "git" at the end of one line
// and "push" at the start of the next match here when grep would stay
// silent on that same input. matchesAnyLine (opsctx.go) is what supplies
// the per-line semantics instead.
var pushWithoutPR = regexp.MustCompile(`(^|[[:space:];&|])git[[:space:]]+((-C|-c)[[:space:]]*[^[:space:]]+[[:space:]]+|-[^[:space:]]+[[:space:]]+)*push([[:space:]]|$)`)

func toolResponseText(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case map[string]any:
		stdout, _ := t["stdout"].(string)
		stderr, _ := t["stderr"].(string)
		output, _ := t["output"].(string)
		return stdout + "\n" + stderr + "\n" + output
	default:
		return ""
	}
}

type bashhintOutput struct {
	HookSpecificOutput struct {
		HookEventName     string `json:"hookEventName"`
		AdditionalContext string `json:"additionalContext"`
	} `json:"hookSpecificOutput"`
}

func runBashhint(_ []string) {
	raw, err := io.ReadAll(os.Stdin)
	if err != nil {
		return
	}

	var in map[string]any
	if err := json.Unmarshal(raw, &in); err != nil {
		return
	}

	out := toolResponseText(in["tool_response"])
	if out == "" {
		return
	}
	cmd, _ := dig(in, "tool_input", "command").(string)

	hint := ""
	switch {
	case strings.Contains(out, "Create a pull request for") || strings.Contains(out, "/pull/new/"):
		// NOTE: GitHub prints this on push only while the branch has no PR —
		// so the push output itself is the check, no gh call needed.
		if matchesAnyLine(pushWithoutPR, cmd) {
			hint = "Пуш прошёл, а PR для ветки нет — GitHub предлагает его создать. Последний шаг DELEGATED-запуска — `gh pr create`, не ссылка в отчёте."
		}
	case strings.Contains(out, "control characters that would be hidden"):
		hint = `Управляющий символ попал в команду литералом. Отклоняется валидацией ДО исполнения, поэтому предотвратить это хуком нельзя — только не писать так. Собирай символ через printf в переменную: SEP=$(printf '\037') и дальше передавай "$SEP".`
	case strings.Contains(out, "Illegal byte sequence"):
		hint = "BSD-утилита споткнулась о многобайтный UTF-8. Либо `LC_ALL=C` перед командой (если байты и нужны как байты), либо не гонять текст с не-ASCII через cut/sed/tr — python или awk справятся."
	case strings.Contains(out, "command not found: timeout") || strings.Contains(out, "timeout: command not found"):
		hint = "GNU `timeout` на macOS нет. Есть `gtimeout` из coreutils, либо запусти через run_in_background и не ограничивай время вовсе."
	case strings.Contains(out, "no matches found:"):
		hint = "zsh считает глоб без совпадений ошибкой, а не пустым списком. Закавычь шаблон и отдай его самой команде (`find … -name '*.log'`), либо `setopt null_glob` в этом же вызове."
	case strings.Contains(out, "sed: -i may not be used") || strings.Contains(out, `sed: 1: "`) || strings.Contains(out, "invalid command code"):
		hint = "BSD `sed -i` требует суффикс: `sed -i '' 's/…/…/' file`. Для правки файла в репозитории надёжнее Edit — он не зависит от диалекта sed."
	case strings.Contains(out, "unmatched '") || strings.Contains(out, `unmatched "`) || strings.Contains(out, "unexpected EOF while looking for matching"):
		hint = "Незакрытая кавычка. Если внутри вложенный `python -c` или `perl -e` — вынеси код в heredoc или временный файл вместо того, чтобы вкладывать кавычки в кавычки."
	case strings.Contains(out, "Operation not permitted"):
		if strings.Contains(cmd, "docker") || strings.Contains(cmd, "ip netns") || strings.Contains(cmd, "mount") {
			hint = "Похоже на нехватку capability, а не на права файла: netns/mount нужен привилегированный контейнер. Не обходи — сообщи владельцу."
		}
	}

	if hint == "" {
		return
	}

	// NOTE: the hook is registered on two events (PostToolUse and
	// PostToolUseFailure), and the name must match the one that arrived or
	// the output risks being discarded.
	event, _ := in["hook_event_name"].(string)
	if event == "" {
		event = "PostToolUse"
	}

	var res bashhintOutput
	res.HookSpecificOutput.HookEventName = event
	res.HookSpecificOutput.AdditionalContext = "Знакомая грабля: " + hint
	emitJSON(res)
}
