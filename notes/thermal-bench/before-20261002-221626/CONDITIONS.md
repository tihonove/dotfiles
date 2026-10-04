# Условия прогона before (02.10.2026, 22:16–23:02 CEST)

- Ubuntu 24.04, ядро 6.14.0-36-generic, BIOS R1SET55W (1.26), GNOME wayland
- power-profiles-daemon: balanced, EPP balance_performance, thermald не запущен
- RAPL PL1 = PL2 = 55 Вт (MSR и MMIO), окно long_term 27983872 мкс
- Зарядка подключена, батарея Not charging (62%, порог), аптайм ~4,5 дня
- NVIDIA MX550: runtime_status = active во всех фазах
- Открыт и простаивал Google Chrome (load ~0,2); btop закрыт
- Вентилятор: авто (thinkpad_acpi fan_control=0)
- Температура в комнате: НЕ ЗАПИСАНА (дописать: thermal_bench.py ambient <папка> <°C>)
- Счётчик package_throttle_count до прогона: 104992, после: 230376

Чтобы прогон «after» был сравним: те же ядро/BIOS/профиль/лимиты, Chrome открыт и простаивает,
та же поверхность, крышка открыта, зарядка подключена, батарея Not charging.
