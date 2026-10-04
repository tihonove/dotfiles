#!/usr/bin/env python3
"""Воспроизводимый термотест ноутбука: до и после чистки.

Запуск (нужен root для RAPL и лимитов мощности):
    sudo python3 thermal_bench.py run --label before --ambient 23.5
    sudo python3 thermal_bench.py run --label after  --ambient 23.0
    python3 thermal_bench.py compare results/before-* results/after-*

Фазы:
  1. idle     — покой, система успокаивается
  2. fixed    — нагрузка на все потоки при жёстком лимите мощности (по умолчанию 20 Вт).
                Мощность одинаковая в обоих прогонах, поэтому разница в температуре
                отражает только охлаждение. Главная метрика: (T - ambient) / W, °C/Вт.
  3. max      — нагрузка с родными лимитами: сколько ватт и работы система держит долго.
  4. cooldown — сколько секунд остывает обратно.
"""
import argparse, glob, hashlib, json, multiprocessing as mp, os, platform, signal, sys, time
from pathlib import Path

RAPL_ZONES = ["/sys/class/powercap/intel-rapl:0", "/sys/class/powercap/intel-rapl-mmio:0"]
ENERGY = "/sys/class/powercap/intel-rapl:0/energy_uj"
ENERGY_MAX = "/sys/class/powercap/intel-rapl:0/max_energy_range_uj"
FAN = "/proc/acpi/ibm/fan"
BAT = "/sys/class/power_supply/BAT0"


def rd(path, default=None):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return default


def hwmon(name, sensor):
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        if rd(f"{h}/name") == name:
            v = rd(f"{h}/{sensor}")
            if v is not None:
                return int(v)
    return None


def pkg_temp():
    for z in glob.glob("/sys/class/thermal/thermal_zone*"):
        if rd(f"{z}/type") == "x86_pkg_temp":
            return int(rd(f"{z}/temp")) / 1000
    return None


def core_temps():
    """{'Core 0': 50.0, ...} из coretemp; у E-ядер один датчик на кластер из 4 ядер."""
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        if rd(f"{h}/name") == "coretemp":
            out = {}
            for lab in sorted(glob.glob(f"{h}/temp*_label")):
                name = rd(lab)
                if name and name.startswith("Core"):
                    out[name] = int(rd(lab.replace("_label", "_input"))) / 1000
            return dict(sorted(out.items(), key=lambda kv: int(kv[0].split()[1])))
    return {}


def avg_freq_mhz():
    fs = [int(rd(f)) for f in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq")]
    return sum(fs) / len(fs) / 1000 if fs else None


def throttle_count():
    return int(rd("/sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count", "0"))


def nvidia_state():
    return rd("/sys/bus/pci/devices/0000:02:00.0/power/runtime_status")


# ---------- нагрузка ----------

def _worker(counter, stop):
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    buf = os.urandom(1 << 20)
    n = 0
    while not stop.is_set():
        hashlib.sha256(buf).digest()
        n += 1
        if n == 8:
            counter.value += 8
            n = 0


class Load:
    def __init__(self, nproc):
        self.stop = mp.Event()
        self.counters = [mp.Value("Q", 0, lock=False) for _ in range(nproc)]
        self.procs = [mp.Process(target=_worker, args=(c, self.stop), daemon=True) for c in self.counters]

    def __enter__(self):
        for p in self.procs:
            p.start()
        return self

    def ops(self):
        return sum(c.value for c in self.counters)

    def __exit__(self, *a):
        self.stop.set()
        for p in self.procs:
            p.join(5)


# ---------- лимиты мощности и вентилятор ----------

def read_limits():
    out = {}
    for z in RAPL_ZONES:
        for c in (0, 1):
            f = f"{z}/constraint_{c}_power_limit_uw"
            if os.path.exists(f):
                out[f] = rd(f)
    return out


def write_limits(limits):
    for f, v in limits.items():
        try:
            Path(f).write_text(str(v))
        except OSError as e:
            print(f"  ! не удалось записать {f}: {e}", file=sys.stderr)


def set_fan(level):
    try:
        Path(FAN).write_text(f"level {level}\n")
        return True
    except OSError:
        return False


# ---------- измерение ----------

class Sampler:
    BASE = ["t", "phase", "pkg_c", "ec_cpu_c", "fan_rpm", "pkg_w", "mhz", "ops", "core_max_c", "core_min_c", "core_spread_c"]

    def __init__(self, csv):
        self.csv = csv
        self.cores = list(core_temps())
        self.cols = self.BASE + [c.replace(" ", "").lower() + "_c" for c in self.cores]
        csv.write(",".join(self.cols) + "\n")
        self.emax = int(rd(ENERGY_MAX, "0"))
        self.e0 = int(rd(ENERGY))
        self.t0 = time.monotonic()

    def sample(self, phase, load=None):
        time.sleep(1)
        e1, t1 = int(rd(ENERGY)), time.monotonic()
        de = e1 - self.e0 if e1 >= self.e0 else e1 + self.emax - self.e0
        watts = de / 1e6 / (t1 - self.t0)
        self.e0, self.t0 = e1, t1
        s = {
            "t": round(time.time(), 1), "phase": phase,
            "pkg_c": pkg_temp(), "ec_cpu_c": (hwmon("thinkpad", "temp1_input") or 0) / 1000,
            "fan_rpm": hwmon("thinkpad", "fan1_input"), "pkg_w": round(watts, 2),
            "mhz": round(avg_freq_mhz() or 0), "ops": load.ops() if load else 0,
        }
        ct = core_temps()
        v = list(ct.values())
        s["core_max_c"], s["core_min_c"] = (max(v), min(v)) if v else (None, None)
        s["core_spread_c"] = round(max(v) - min(v), 1) if v else None
        for c in self.cores:
            s[c.replace(" ", "").lower() + "_c"] = ct.get(c)
        self.csv.write(",".join(str(s[k]) for k in self.cols) + "\n")
        self.csv.flush()
        return s


def summarize(samples, tail_s, ambient):
    tail = samples[-tail_s:]
    avg = lambda k: sum(s[k] for s in tail) / len(tail)
    r = {k: round(avg(k), 2) for k in ("pkg_c", "ec_cpu_c", "fan_rpm", "pkg_w", "mhz")}
    r["pkg_c_max"] = max(s["pkg_c"] for s in samples)
    sp = [s["core_spread_c"] for s in tail if s.get("core_spread_c") is not None]
    if sp:
        r["core_spread_c"] = round(sum(sp) / len(sp), 2)
        r["core_spread_c_max"] = max(s["core_spread_c"] for s in samples if s.get("core_spread_c") is not None)
    if len(tail) > 1 and tail[-1]["ops"]:
        r["ops_per_s"] = round((tail[-1]["ops"] - tail[0]["ops"]) / (tail[-1]["t"] - tail[0]["t"]), 1)
    if ambient is not None and r["pkg_w"] > 1:
        r["c_per_w"] = round((r["pkg_c"] - ambient) / r["pkg_w"], 3)
    if ambient is not None:
        r["delta_ambient_c"] = round(r["pkg_c"] - ambient, 2)
    return r


def rise(samples, t0):
    """Как быстро растёт температура в начале нагрузки: плохая паста даёт скачок за секунды.
    t0 — температура непосредственно перед нагрузкой; c_at_Ns — через N секунд нагрузки."""
    at = lambda i: samples[min(i, len(samples) - 1)]["pkg_c"]
    first = lambda thr: next((i + 1 for i, s in enumerate(samples) if s["pkg_c"] >= thr), None)
    return {"start_c": t0, "c_at_1s": at(0), "c_at_3s": at(2), "c_at_10s": at(9), "c_at_30s": at(29),
            "s_to_90c": first(90), "s_to_95c": first(95)}


def snapshot():
    return {"limits": read_limits(), "nvidia": nvidia_state(), "throttle_count": throttle_count(),
            "pkg_c": pkg_temp(), "platform_profile": rd("/sys/firmware/acpi/platform_profile"),
            "epp": rd("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference")}


def phase(name, seconds, sampler, load=None, live=True):
    samples = []
    for i in range(seconds):
        s = sampler.sample(name, load)
        samples.append(s)
        if live and i % 10 == 0:
            print(f"  [{name} {i:4d}/{seconds}s] {s['pkg_c']:5.1f}°C  {s['pkg_w']:5.1f} Вт  "
                  f"{s['fan_rpm']} rpm  {s['mhz']} МГц", flush=True)
    return samples


def run(a):
    if os.geteuid() != 0:
        sys.exit("Нужен root: sudo python3 thermal_bench.py run ...")
    if rd("/sys/class/power_supply/AC/online") != "1":
        sys.exit("Подключи зарядку: без неё лимиты мощности другие, сравнение некорректно.")
    bat_status = rd(f"{BAT}/status")
    if bat_status == "Charging":
        print("! Батарея заряжается — это лишнее тепло в корпусе. Лучше дождаться полной зарядки.")

    stamp = time.strftime("%Y%m%d-%H%M%S")
    out = Path(__file__).resolve().parent / "results" / f"{a.label}-{stamp}"
    out.mkdir(parents=True)
    d = dict(idle=a.idle, fixed=a.fixed, max=a.max)
    if a.quick:
        d = dict(idle=120, fixed=180, max=180)

    meta = {
        "label": a.label, "ambient_c": a.ambient, "fixed_watts": a.watts, "fixed_fan": a.fan_level,
        "kernel": platform.release(), "bios": rd("/sys/class/dmi/id/bios_version"),
        "platform_profile": rd("/sys/firmware/acpi/platform_profile"),
        "epp": rd("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"),
        "battery_status": bat_status, "battery_capacity": rd(f"{BAT}/capacity"),
        "nvidia_runtime_status": nvidia_state(), "orig_limits": read_limits(), "durations": d,
        "time_windows": {f: rd(f) for z in RAPL_ZONES for f in glob.glob(f"{z}/constraint_*_time_window_us")},
        "cores": core_temps(), "uptime_s": float(rd("/proc/uptime", "0").split()[0]),
        "throttle_count_at_start": throttle_count(),
    }
    if meta["nvidia_runtime_status"] != "suspended":
        print("! NVIDIA не спит (runtime_status != suspended) — она подогревает общую тепловую трубку. "
              "Зафиксируй это одинаково в обоих прогонах.")
    print(f"Результаты: {out}\nУсловия: {json.dumps({k: meta[k] for k in ('ambient_c', 'platform_profile', 'epp', 'battery_status', 'nvidia_runtime_status')}, ensure_ascii=False)}")

    orig = meta["orig_limits"]
    fixed_fan = a.fan_level is not None and set_fan(a.fan_level)
    if a.fan_level is not None and not fixed_fan:
        print("! Вентилятор зафиксировать не вышло (нужен thinkpad_acpi fan_control=1), остаётся auto.")
        meta["fixed_fan"] = None

    csv = open(out / "samples.csv", "w")
    sampler = Sampler(csv)
    res = {"meta": meta, "snapshots": {}}
    t_start = throttle_count()
    try:
        print(f"\n1/4 Покой {d['idle']} с — не трогай ноутбук")
        s = phase("idle", d["idle"], sampler)
        res["idle"] = summarize(s, min(120, len(s)), a.ambient)
        idle_c = res["idle"]["pkg_c"]

        res["snapshots"]["fixed"] = snapshot()
        print(f"\n2/4 Фиксированная мощность {a.watts} Вт, {d['fixed']} с")
        uw = str(int(a.watts * 1e6))
        write_limits({f: uw for f in orig})
        with Load(os.cpu_count()) as load:
            s = phase("fixed", d["fixed"], sampler, load)
        res["fixed"] = summarize(s, min(180, len(s) // 2), a.ambient)
        res["fixed"].update(rise(s, res["snapshots"]["fixed"]["pkg_c"]))
        write_limits(orig)

        # Ждём не фиксированное время, а пока не остынет: иначе max стартует с остаточным теплом
        # и «скачок до Tjmax» нельзя отличить от недоостывания.
        rest_target = idle_c + a.rest_margin
        print(f"\n   пауза: ждём {rest_target:.1f} °C (idle + {a.rest_margin}), не дольше {a.rest_max} с")
        rest = 0
        for rest in range(1, a.rest_max + 1):
            if sampler.sample("rest")["pkg_c"] <= rest_target and rest >= 30:
                break
        res["rest_s"] = rest
        res["snapshots"]["max"] = snapshot()
        if res["snapshots"]["max"]["limits"] != orig:
            print("! Лимиты RAPL после восстановления не совпадают с исходными!")

        print(f"\n3/4 Максимальная нагрузка с родными лимитами, {d['max']} с")
        th0 = throttle_count()
        with Load(os.cpu_count()) as load:
            s = phase("max", d["max"], sampler, load)
        res["max"] = summarize(s, min(180, len(s) // 2), a.ambient)
        res["max"]["first_30s_w"] = round(sum(x["pkg_w"] for x in s[:30]) / len(s[:30]), 2)
        res["max"]["throttle_events"] = throttle_count() - th0
        res["max"].update(rise(s, res["snapshots"]["max"]["pkg_c"]))

        print("\n4/4 Остывание (до idle + 5 °C, максимум 300 с)")
        target, cool = idle_c + 5, None
        for i in range(300):
            if sampler.sample("cooldown")["pkg_c"] <= target:
                cool = i + 1
                break
        res["cooldown_s"] = cool
    finally:
        write_limits(orig)
        if fixed_fan:
            set_fan("auto")
        csv.close()

    res["throttle_events_total"] = throttle_count() - t_start
    res["snapshots"]["end"] = snapshot()
    (out / "summary.json").write_text(json.dumps(res, ensure_ascii=False, indent=2))
    print_summary(res)
    print(f"\nСохранено в {out}")


def print_summary(r):
    print(f"\n=== {r['meta']['label']} (ambient {r['meta']['ambient_c']} °C) ===")
    for p in ("idle", "fixed", "max"):
        print(f"{p:6s} {json.dumps(r[p], ensure_ascii=False)}")
    print(f"rest_s {r.get('rest_s')}  cooldown_s {r['cooldown_s']}")


ROWS = [
    ("idle", "pkg_c", "Покой: температура, °C", -1),
    ("idle", "fan_rpm", "Покой: вентилятор, rpm", -1),
    ("fixed", "c_per_w", "Фикс. мощность: °C на ватт  ← главное", -1),
    ("fixed", "delta_ambient_c", "Фикс. мощность: перегрев над комнатой, °C", -1),
    ("fixed", "fan_rpm", "Фикс. мощность: вентилятор, rpm", -1),
    ("fixed", "core_spread_c", "Фикс. мощность: разброс между ядрами, °C", -1),
    ("fixed", "c_at_10s", "Фикс. мощность: °C через 10 с", -1),
    ("fixed", "pkg_w", "Фикс. мощность: реальные ватты (контроль)", 0),
    ("max", "pkg_w", "Макс: устойчивая мощность, Вт", 1),
    ("max", "ops_per_s", "Макс: работа, оп/с", 1),
    ("max", "mhz", "Макс: средняя частота, МГц", 1),
    ("max", "pkg_c", "Макс: температура, °C", -1),
    ("max", "first_30s_w", "Макс: мощность первые 30 с, Вт", 1),
    ("max", "start_c", "Макс: старт с температуры, °C (контроль)", 0),
    ("max", "c_at_3s", "Макс: °C через 3 с", -1),
    ("max", "s_to_95c", "Макс: секунд до 95 °C", 1),
    ("max", "core_spread_c", "Макс: разброс между ядрами, °C", -1),
    ("max", "throttle_events", "Макс: событий троттлинга", -1),
    (None, "cooldown_s", "Остывание, с", -1),
]


def compare(a):
    b, c = (json.loads((Path(p) / "summary.json").read_text()) for p in (a.before, a.after))
    print(f"{'':48s}{'до':>10s}{'после':>10s}{'Δ':>10s}")
    for ph, k, title, better in ROWS:
        x = (b.get(ph) or {}).get(k) if ph else b.get(k)
        y = (c.get(ph) or {}).get(k) if ph else c.get(k)
        if x is None or y is None:
            print(f"{title:48s}{str(x):>10s}{str(y):>10s}")
            continue
        dlt = y - x
        pct = f" ({dlt / x * 100:+.0f}%)" if x else ""
        mark = "" if better == 0 or dlt == 0 else (" ✓" if dlt * better > 0 else " ✗")
        print(f"{title:48s}{x:>10.2f}{y:>10.2f}{dlt:>+10.2f}{pct}{mark}")
    keys = ("kernel", "bios", "platform_profile", "epp", "orig_limits", "nvidia_runtime_status", "fixed_fan", "fixed_watts")
    diff = [k for k in keys if b["meta"].get(k) != c["meta"].get(k)]
    if diff:
        print(f"\n!!! Условия различаются: {', '.join(diff)} — сравнение под вопросом")
    for side, r in (("до", b), ("после", c)):
        m = r["meta"]
        print(f"\nУсловия {side}: ambient={m['ambient_c']} profile={m['platform_profile']} epp={m['epp']} "
              f"bat={m['battery_status']} nvidia={m['nvidia_runtime_status']} fan={m['fixed_fan']} "
              f"kernel={m['kernel']} bios={m['bios']}")


def set_ambient(a):
    """Дописать температуру в комнате в уже готовый прогон и пересчитать °C/Вт."""
    f = Path(a.result) / "summary.json"
    r = json.loads(f.read_text())
    r["meta"]["ambient_c"] = a.ambient
    for ph in ("idle", "fixed", "max"):
        x = r.get(ph)
        if x:
            x["delta_ambient_c"] = round(x["pkg_c"] - a.ambient, 2)
            if x["pkg_w"] > 1:
                x["c_per_w"] = round((x["pkg_c"] - a.ambient) / x["pkg_w"], 3)
    f.write_text(json.dumps(r, ensure_ascii=False, indent=2))
    print_summary(r)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd", required=True)
    r = sp.add_parser("run")
    r.add_argument("--label", required=True)
    r.add_argument("--ambient", type=float, help="температура в комнате, °C (очень желательно)")
    r.add_argument("--watts", type=float, default=20.0, help="лимит для фазы fixed")
    r.add_argument("--fan-level", help="зафиксировать вентилятор (0-7), нужен thinkpad_acpi fan_control=1")
    r.add_argument("--idle", type=int, default=600)
    r.add_argument("--fixed", type=int, default=600)
    r.add_argument("--max", type=int, default=600)
    r.add_argument("--rest-margin", type=float, default=3.0, help="пауза до idle + N °C перед max")
    r.add_argument("--rest-max", type=int, default=600, help="предел паузы перед max, с")
    r.add_argument("--quick", action="store_true", help="короткий прогон для проверки скрипта")
    c = sp.add_parser("compare")
    c.add_argument("before")
    c.add_argument("after")
    e = sp.add_parser("ambient", help="дописать температуру в комнате в готовый прогон")
    e.add_argument("result")
    e.add_argument("ambient", type=float)
    a = p.parse_args()
    {"run": run, "compare": compare, "ambient": set_ambient}[a.cmd](a)


if __name__ == "__main__":
    main()
