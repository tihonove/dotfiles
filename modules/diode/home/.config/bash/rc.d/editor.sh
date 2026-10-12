# diode — редактор по умолчанию для всего, что спрашивает $EDITOR/$VISUAL:
# crontab -e, sudoedit, `v` в less, Ctrl+G в Claude Code, fc и прочее. Git
# свой core.editor берёт из ~/.config/git/diode.conf и без этих переменных —
# он нужен и там, где git зовут не из интерактивного шелла.
#
# Лежит в модуле diode, а не в core, по той же причине, что и core.editor:
# на машине без diode (dev-контейнер) $EDITOR=diode ломал бы всё перечисленное.
#
# В имени нет «vi» — это важно: tmux включает mode-keys vi, если видит «vi» в
# $EDITOR/$VISUAL, а бинды copy-mode в tmux.conf рассчитаны на emacs.
export EDITOR=diode
export VISUAL=diode
