# Website Load Test with k6 | تست بار وب‌سایت با k6

[فارسی](#فارسی) · [English](#english)

> [!WARNING]
> Only test systems that you own or are explicitly authorized to test. Start with a low load and monitor the target.
>
> فقط سامانه‌ای را تست کنید که مالک آن هستید یا برای تست آن مجوز صریح دارید. با بار کم شروع کنید و مقصد را زیر نظر داشته باشید.

## فارسی

ابزاری سبک و قابل تنظیم برای تست بار هر وب‌سایت HTTP/HTTPS با [k6](https://grafana.com/docs/k6/latest/). پروژه برای WordPress تنظیمات نمونه دارد، اما به WordPress وابسته نیست و روی Windows و Linux اجرا می‌شود.

### امکانات

- تست هر وب‌سایت HTTP یا HTTPS، از صفحه اصلی تا مسیرهای دلخواه
- دو حالت اجرا: کاربر مجازی (`vus`) و نرخ ثابت درخواست (`rps`)
- افزایش و کاهش تدریجی بار در حالت VU
- آستانه‌های آماده برای نرخ خطا و زمان پاسخ p95/p99
- متریک‌های اختصاصی `site_page_duration` و `site_5xx_rate`
- اجراکننده PowerShell برای Windows و Bash برای Linux
- سرویس اختیاری دریافت، تست، کش و انتخاب پروکسی
- providerهای HTTP، SOCKS4 و SOCKS5 با فایل JSON قابل ویرایش
- حذف خودکار IPهای خصوصی/رزروشده و محدودیت اندازه، تعداد، timeout و concurrency
- جلوگیری از fallback ناخواسته روی IP اصلی هنگام فعال‌بودن حالت پروکسی

### کلون و نصب

```bash
git clone https://github.com/ZamaniDeveloper/wordpress-load-test.git
cd wordpress-load-test
```

نصب k6 روی Windows:

```powershell
winget install k6 --source winget
k6 version
Copy-Item .env.example .env
```

نصب k6 روی Debian/Ubuntu:

```bash
sudo gpg -k
curl -fsSL https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6 python3 curl
cp .env.example .env
chmod +x run-load-test.sh
```

Fedora/CentOS:

```bash
sudo dnf install https://dl.k6.io/rpm/repo.rpm
sudo dnf install k6 python3 curl
cp .env.example .env
chmod +x run-load-test.sh
```

### تنظیم و اجرا

حداقل `TARGET_URL` و مسیرهای موردنیاز را در `.env` تنظیم کنید:

```env
TARGET_URL=https://example.com
MODE=vus
VUS=10
RAMP_UP=1m
HOLD=3m
RAMP_DOWN=1m
PATHS=/,/pricing,/contact
```

Windows:

```powershell
.\run-load-test.ps1
```

Linux:

```bash
./run-load-test.sh
```

اجرای مستقیم و بدون launcher نیز ممکن است:

```bash
TARGET_URL=https://example.com PATHS=/,/about k6 run site-load-test.js
```

برای WordPress فقط مسیرها را متناسب با سایت تغییر دهید:

```env
PATHS=/,/blog/,/?s=wordpress,/wp-json/
```

### تنظیمات اصلی

| متغیر | کاربرد | نمونه |
|---|---|---|
| `TARGET_URL` | آدرس پایه سایت هدف | `https://example.com` |
| `PATHS` | مسیرهای جداشده با کاما | `/,/pricing,/contact` |
| `MODE` | روش اجرا: `vus` یا `rps` | `rps` |
| `SLEEP` | مکث میان تکرارهای هر VU | `1` |
| `VUS` | تعداد کاربران مجازی | `10` |
| `RAMP_UP` / `HOLD` / `RAMP_DOWN` | مراحل حالت VU | `1m` / `3m` / `1m` |
| `RATE` / `TIME_UNIT` / `DURATION` | نرخ و مدت حالت RPS | `100` / `1s` / `3m` |
| `PRE_ALLOCATED_VUS` / `MAX_VUS` | ظرفیت حالت RPS | `80` / `250` |

### حالت پروکسی

این حالت پیش‌فرض خاموش است. برای فعال‌کردن آن:

```env
USE_PROXY=true
PROXY_PROVIDERS_FILE=proxy-providers.json
MAX_PROXY_CANDIDATES=30
MAX_WORKING_PROXIES=5
PROXY_TEST_CONCURRENCY=10
PROXY_CACHE_MINUTES=60
PROXY_TEST_URL=
```

فایل [`proxy-providers.json`](proxy-providers.json) شامل منابع درخواستی TheSpeedX برای HTTP، SOCKS4 و SOCKS5 و منابع Proxifly است. نگاشت typeها:

| Type | پروتکل | امکان انتخاب برای k6 |
|---:|---|---|
| `1` | HTTP | بله |
| `4` | SOCKS4 | فقط دریافت، تست و ذخیره |
| `5` | SOCKS5 | بله |

SOCKS4 توسط transport استاندارد k6 پشتیبانی نمی‌شود؛ بنابراین اعتبارسنجی و در فایل ذخیره می‌شود اما launcher آن را برای k6 انتخاب نمی‌کند. HTTP و SOCKS5 قابل انتخاب‌اند. هر اجرای k6 فقط یک پروکسی سالم انتخاب می‌کند و برای توزیع میان چند پروکسی باید چند فرایند جدا اجرا شود.

تازه‌سازی دستی در Windows:

```powershell
.\Update-ProxyPool.ps1 -TestUrl "https://example.com" -MaxCandidates 50 -MaxWorking 10
```

تازه‌سازی دستی در Linux:

```bash
python3 proxy_pool.py --providers proxy-providers.json --test-url https://example.com --max-candidates 50 --max-working 10
```

`MAX_WORKING_PROXIES` سقف ذخیره برای هر پروتکل است. پروکسی‌های سالم در `.proxy-cache/working-proxies.txt` ذخیره می‌شوند و این پوشه در Git ثبت نمی‌شود. اگر هیچ HTTP یا SOCKS5 سالمی وجود نداشته باشد، اجرای k6 متوقف می‌شود.

> [!CAUTION]
> پروکسی عمومی قابل اعتماد یا محرمانه نیست. کوکی ورود، توکن، رمز عبور یا داده حساس را از آن عبور ندهید. پروکسی می‌تواند نتیجه latency را نیز مخدوش کند؛ برای benchmark دقیق، تست مستقیم و تست proxy را جدا گزارش کنید.

---

## English

A lightweight, configurable [k6](https://grafana.com/docs/k6/latest/) load-testing toolkit for any HTTP/HTTPS website. It includes WordPress examples but is not WordPress-specific, and it runs on Windows and Linux.

### Features

- Test any HTTP or HTTPS website with configurable paths
- Virtual-user (`vus`) and constant request-rate (`rps`) modes
- Configurable VU ramp-up, steady load, and ramp-down stages
- Ready-to-use failure and p95/p99 latency thresholds
- Custom `site_page_duration` and `site_5xx_rate` metrics
- PowerShell launcher for Windows and Bash launcher for Linux
- Optional proxy download, validation, caching, and selection service
- Editable JSON providers for HTTP, SOCKS4, and SOCKS5
- Private/reserved IP filtering and bounded size, count, timeout, and concurrency
- Hard failure instead of silently exposing the direct IP when proxy mode is enabled

### Clone and install

```bash
git clone https://github.com/ZamaniDeveloper/wordpress-load-test.git
cd wordpress-load-test
```

Windows:

```powershell
winget install k6 --source winget
k6 version
Copy-Item .env.example .env
```

Debian/Ubuntu:

```bash
sudo gpg -k
curl -fsSL https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6 python3 curl
cp .env.example .env
chmod +x run-load-test.sh
```

Fedora/CentOS:

```bash
sudo dnf install https://dl.k6.io/rpm/repo.rpm
sudo dnf install k6 python3 curl
cp .env.example .env
chmod +x run-load-test.sh
```

### Configure and run

Edit `.env` and set at least the target URL and paths:

```env
TARGET_URL=https://example.com
MODE=vus
VUS=10
RAMP_UP=1m
HOLD=3m
RAMP_DOWN=1m
PATHS=/,/pricing,/contact
```

Windows:

```powershell
.\run-load-test.ps1
```

Linux:

```bash
./run-load-test.sh
```

Direct execution without a launcher:

```bash
TARGET_URL=https://example.com PATHS=/,/about k6 run site-load-test.js
```

For WordPress, simply use WordPress-specific paths:

```env
PATHS=/,/blog/,/?s=wordpress,/wp-json/
```

### Main configuration

| Variable | Purpose | Example |
|---|---|---|
| `TARGET_URL` | Target site's base URL | `https://example.com` |
| `PATHS` | Comma-separated paths | `/,/pricing,/contact` |
| `MODE` | `vus` or `rps` execution mode | `rps` |
| `SLEEP` | Delay between VU iterations | `1` |
| `VUS` | Virtual-user count | `10` |
| `RAMP_UP` / `HOLD` / `RAMP_DOWN` | VU stages | `1m` / `3m` / `1m` |
| `RATE` / `TIME_UNIT` / `DURATION` | RPS rate and duration | `100` / `1s` / `3m` |
| `PRE_ALLOCATED_VUS` / `MAX_VUS` | RPS-mode capacity | `80` / `250` |

### Proxy mode

Proxy mode is disabled by default. Enable it with:

```env
USE_PROXY=true
PROXY_PROVIDERS_FILE=proxy-providers.json
MAX_PROXY_CANDIDATES=30
MAX_WORKING_PROXIES=5
PROXY_TEST_CONCURRENCY=10
PROXY_CACHE_MINUTES=60
PROXY_TEST_URL=
```

[`proxy-providers.json`](proxy-providers.json) includes the requested TheSpeedX HTTP, SOCKS4, and SOCKS5 sources plus Proxifly sources. Provider type mapping:

| Type | Protocol | Selectable by k6 |
|---:|---|---|
| `1` | HTTP | Yes |
| `4` | SOCKS4 | Download, validation, and storage only |
| `5` | SOCKS5 | Yes |

The standard k6 transport does not support SOCKS4, so SOCKS4 entries are validated and cached but never selected by the launcher. HTTP and SOCKS5 are selectable. One k6 process uses one working proxy; start separate processes to use multiple proxies.

Manual refresh on Windows:

```powershell
.\Update-ProxyPool.ps1 -TestUrl "https://example.com" -MaxCandidates 50 -MaxWorking 10
```

Manual refresh on Linux:

```bash
python3 proxy_pool.py --providers proxy-providers.json --test-url https://example.com --max-candidates 50 --max-working 10
```

`MAX_WORKING_PROXIES` is the storage limit per protocol. Working proxies are stored in `.proxy-cache/working-proxies.txt`, which is excluded from Git. The launcher stops if it cannot find a working HTTP or SOCKS5 proxy.

> [!CAUTION]
> Public proxies are neither trusted nor private. Never send login cookies, tokens, passwords, or sensitive data through them. Proxies also distort latency measurements, so report direct and proxied benchmarks separately.
