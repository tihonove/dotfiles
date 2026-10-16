// URL от content.js — в native host, тот запускает browser-here. Хост не
// поставлен, упал или не нашёл browser-here — открываем ссылку как открыл бы
// Chrome: пусть не на том столе, но не потерять.
chrome.runtime.onMessage.addListener(({ url }) => {
    chrome.runtime.sendNativeMessage('dev.tihonove.browser_here', { url }, (reply) => {
        if (chrome.runtime.lastError || !reply?.ok) {
            console.warn('browser-here:', chrome.runtime.lastError?.message ?? reply);
            chrome.tabs.create({ url });
        }
    });
});
