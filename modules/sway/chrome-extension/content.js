// Клик по внешней ссылке в окне приложения (PWA) — отдать URL в browser-here,
// а не Chrome: сам он открыл бы вкладку в последнем активном окне, на каком бы
// столе оно ни стояло. Зачем и как устроено — в README рядом.

// Только окна приложений. Тот же Slack во вкладке живёт в обычном окне, и там
// новая вкладка и так открывается где надо.
if (!matchMedia('(display-mode: browser)').matches) {
    // Свой домен приложение открывает у себя: ссылка на сообщение из другого
    // канала — app.slack.com и <workspace>.slack.com, оба под slack.com.
    const home = location.hostname.split('.').slice(-2).join('.');

    const own = (host) => host === home || host.endsWith('.' + home);

    const onClick = (e) => {
        // Левая и средняя кнопки; правая — контекстное меню, его не трогаем.
        if (e.button > 1) return;
        const a = e.composedPath().find((n) => n instanceof HTMLAnchorElement && n.href);
        if (!a) return;
        let url;
        try { url = new URL(a.href); } catch { return; }
        if (!/^https?:$/.test(url.protocol) || own(url.hostname)) return;

        // capture на window — раньше любого обработчика страницы, так что
        // свой переход Slack уже не начнёт.
        e.preventDefault();
        e.stopImmediatePropagation();
        chrome.runtime.sendMessage({ url: url.href });
    };

    addEventListener('click', onClick, true);
    addEventListener('auxclick', onClick, true);
}
