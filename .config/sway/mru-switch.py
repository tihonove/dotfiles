#!/usr/bin/env python3
# MRU-переключение окон текущего рабочего стола — аналог Alt+Tab в Windows.
#
# Своими силами sway этого не умеет: `focus next/prev` ходит по дереву раскладки
# (кто где лежит), а не по времени последней активности. Демон слушает события
# IPC и держит список окон в порядке MRU (most recently used).
#
# Транспорт для горячих клавиш — тоже события sway. В конфиге стоит
#     bindsym --to-code --no-repeat $mod+Tab nop mru-next
# и на каждое нажатие sway присылает событие binding с текстом команды. Так что
# отдельного клиента и сокета не нужно: нажатие приходит прямо сюда, без задержки
# на запуск процесса. Сама команда `nop` ничего не делает — если демон не запущен,
# клавиша просто молчит.
#
# Поведение как в Windows: пока Tab нажимают часто (реже, чем раз в LOCKIN мс,
# промежуток не считается), список заморожен и мы идём по нему дальше; после паузы
# выбранное окно фиксируется в начале MRU. Поэтому одно нажатие $mod+Tab всегда
# перекидывает между двумя последними окнами, а несколько подряд — уводят глубже.
#
# Только stdlib (i3ipc не нужен): протокол IPC простой — магия, длина, тип, JSON.

import json
import os
import socket
import struct
import sys
import time
from selectors import DefaultSelector, EVENT_READ

MAGIC = b"i3-ipc"
HEADER = struct.Struct("=6sII")
RUN_COMMAND, SUBSCRIBE, GET_TREE = 0, 2, 4
EVENT_WINDOW, EVENT_BINDING, EVENT_TICK = 0x80000003, 0x80000005, 0x80000007

LOCKIN = 0.9          # сек без нажатий, после которых выбор фиксируется в MRU
CMD_NEXT = "nop mru-next"
CMD_PREV = "nop mru-prev"


# ── Протокол sway IPC ─────────────────────────────────────────────────────────

def connect():
    sock = socket.socket(socket.AF_UNIX)
    sock.connect(os.environ["SWAYSOCK"])
    return sock


def send(sock, msg_type, payload=b""):
    sock.sendall(HEADER.pack(MAGIC, len(payload), msg_type) + payload)


def recv_exactly(sock, size):
    buf = b""
    while len(buf) < size:
        chunk = sock.recv(size - len(buf))
        if not chunk:
            raise ConnectionError("sway закрыл IPC-соединение")
        buf += chunk
    return buf


def recv(sock):
    _, length, msg_type = HEADER.unpack(recv_exactly(sock, HEADER.size))
    body = recv_exactly(sock, length)
    return msg_type, json.loads(body) if body else None


def request(sock, msg_type, payload=b""):
    """Синхронный запрос. Только для соединения БЕЗ подписки: после subscribe
    соединение становится потоком событий, и ответ уже не отличить от события."""
    send(sock, msg_type, payload)
    return recv(sock)[1]


# ── Дерево окон ───────────────────────────────────────────────────────────────

def walk(node):
    yield node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        yield from walk(child)


def is_window(node):
    return (node.get("type") in ("con", "floating_con")
            and not node.get("nodes") and not node.get("floating_nodes"))


def focused_workspace_windows(tree):
    """con_id окон рабочего стола, на котором сейчас фокус, в порядке дерева."""
    for output in tree.get("nodes", []):
        for ws in output.get("nodes", []):
            if ws.get("type") != "workspace":
                continue
            nodes = list(walk(ws))
            if any(n.get("focused") for n in nodes):
                return [n["id"] for n in nodes if is_window(n)]
    return []


# ── Состояние ─────────────────────────────────────────────────────────────────

class Switcher:
    def __init__(self, cmd_sock):
        self.cmd = cmd_sock
        self.mru = []          # con_id, самое свежее — первым
        self.ring = []         # замороженный список окон на время перелистывания
        self.pos = 0           # позиция в ring
        self.expected = None   # con_id, чей focus-эвент вызвали мы сами
        self.deadline = None   # когда фиксировать выбор в MRU
        self.seed()

    def seed(self):
        """Стартуем вместе с sway, но окна могут уже быть (например, при
        перезапуске демона) — набиваем MRU текущим содержимым дерева."""
        tree = request(self.cmd, GET_TREE)
        for node in walk(tree):
            if is_window(node):
                (self.mru.insert(0, node["id"]) if node.get("focused")
                 else self.mru.append(node["id"]))

    def touch(self, con_id):
        """Окно стало активным — наверх MRU."""
        if con_id in self.mru:
            self.mru.remove(con_id)
        self.mru.insert(0, con_id)

    def forget(self, con_id):
        if con_id in self.mru:
            self.mru.remove(con_id)
        if con_id in self.ring:
            self.ring.remove(con_id)
            self.pos = min(self.pos, len(self.ring) - 1)

    def cancel_cycle(self):
        self.ring, self.pos, self.expected, self.deadline = [], 0, None, None

    def step(self, direction):
        now = time.monotonic()
        if not (self.ring and self.deadline and now < self.deadline):
            # Новый цикл: берём окна текущего стола в порядке MRU. Те, что MRU
            # ещё не видел (никогда не были в фокусе), уходят в конец.
            here = focused_workspace_windows(self.tree())
            order = [i for i in self.mru if i in here]
            self.ring = order + [i for i in here if i not in order]
            self.pos = 0
        if len(self.ring) < 2:
            return
        self.pos = (self.pos + direction) % len(self.ring)
        target = self.ring[self.pos]
        self.expected = target
        self.deadline = now + LOCKIN
        request(self.cmd, RUN_COMMAND, f"[con_id={target}] focus".encode())

    def tree(self):
        return request(self.cmd, GET_TREE)

    def lock_in(self):
        """Пауза кончилась — то, на чём остановились, становится свежим в MRU."""
        if self.ring:
            self.touch(self.ring[self.pos])
        self.cancel_cycle()

    def on_window_event(self, event):
        change = event.get("change")
        con_id = (event.get("container") or {}).get("id")
        if con_id is None:
            return
        if change == "close":
            self.forget(con_id)
        elif change == "focus":
            if con_id == self.expected:
                self.expected = None      # это наш собственный переход, MRU не трогаем
            else:
                self.cancel_cycle()       # фокус сменили мышью/другой клавишей
                self.touch(con_id)

    def on_binding_event(self, event):
        self.on_command((event.get("binding") or {}).get("command", ""))

    def on_command(self, command):
        # Сравниваем по хвосту: в binding-эвенте приходит вся команда целиком
        # («nop mru-next»), в tick-эвенте — только payload («mru-next»).
        command = command.strip()
        if command.endswith(CMD_NEXT.split()[-1]):
            self.step(+1)
        elif command.endswith(CMD_PREV.split()[-1]):
            self.step(-1)


# ── Цикл событий ──────────────────────────────────────────────────────────────

def main():
    if "SWAYSOCK" not in os.environ:
        sys.exit("SWAYSOCK не задан — демон запускается изнутри sway-сессии")

    events = connect()
    # tick — запасной путь: `swaymsg -t send_tick mru-next` шлётся откуда угодно
    # (удобно проверить руками, и годится как замена nop, если понадобится).
    request(events, SUBSCRIBE, b'["window","binding","tick"]')
    switcher = Switcher(connect())

    with DefaultSelector() as selector:
        selector.register(events, EVENT_READ)
        while True:
            timeout = None
            if switcher.deadline:
                timeout = max(0.0, switcher.deadline - time.monotonic())
            if not selector.select(timeout):
                switcher.lock_in()        # таймаут: фиксируем выбор
                continue
            msg_type, event = recv(events)
            if msg_type == EVENT_WINDOW:
                switcher.on_window_event(event)
            elif msg_type == EVENT_BINDING:
                switcher.on_binding_event(event)
            elif msg_type == EVENT_TICK:
                switcher.on_command(event.get("payload", ""))


if __name__ == "__main__":
    try:
        main()
    except (ConnectionError, KeyboardInterrupt, FileNotFoundError):
        pass                              # sway закончился — заканчиваем и мы
