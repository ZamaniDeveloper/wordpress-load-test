# WordPress Load Test with k6 | تست بار وردپرس با k6

[فارسی](#فارسی) · [English](#english)

> [!WARNING]
> Only test websites that you own or are explicitly authorized to test. Start with a low load and monitor the server.
>
> فقط وب‌سایتی را تست کنید که مالک آن هستید یا برای تست آن مجوز صریح دارید. با بار کم شروع کنید و سرور را زیر نظر داشته باشید.

## فارسی

یک ابزار سبک و قابل تنظیم برای تست بار و فشار وب‌سایت‌های WordPress با [k6](https://grafana.com/docs/k6/latest/). این پروژه می‌تواند با تعداد ثابتی کاربر مجازی یا نرخ ثابت درخواست اجرا شود و شاخص‌های مهمی مانند زمان پاسخ، نرخ شکست و خطاهای 5xx را گزارش کند.

### امکانات

- دو روش اجرا: کاربر مجازی (`vus`) و نرخ ثابت درخواست (`rps`)
- افزایش و کاهش تدریجی بار در حالت VU
- تنظیم نرخ، مدت تست و ظرفیت VU در حالت RPS
- تست تصادفی چند مسیر WordPress با متغیر `PATHS`
- متریک اختصاصی `wordpress_page_duration` برای زمان پاسخ صفحات
- متریک اختصاصی `wordpress_5xx_rate` برای خطاهای سمت سرور
- بررسی خودکار پاسخ‌های غیر 5xx و پاسخ‌های موفق 2xx/3xx
- آستانه‌های آماده برای نرخ خطا و صدک‌های p95 و p99
- حذف بدنه پاسخ‌ها برای کاهش مصرف حافظه در تست‌های سنگین
- اسکریپت PowerShell برای بارگذاری خودکار تنظیمات از `.env`
- سرویس اختیاری دریافت، تست، کش و انتخاب پروکسی عمومی از منابع GitHub

### پیش‌نیازها

- Windows و PowerShell برای استفاده از اسکریپت آماده؛ خود فایل k6 روی سایر سیستم‌عامل‌ها نیز قابل اجرا است.
- نصب [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/)
- Git برای کلون پروژه

نصب k6 در Windows با winget:

```powershell
winget install GrafanaLabs.k6 --source winget
k6 version
```

یا با Chocolatey:

```powershell
choco install k6
k6 version
```

### کلون، نصب و راه‌اندازی

```powershell
git clone https://github.com/ZamaniDeveloper/wordpress-load-test.git
cd wordpress-load-test
Copy-Item .env.example .env
```

فایل `.env` را ویرایش کنید و حداقل `TARGET_URL` را روی آدرس سایتی بگذارید که مجوز تست آن را دارید. سپس اجرا کنید:

```powershell
.\run-webava-light.ps1
```

برای اجرای مستقیم و مستقل از PowerShell:

```bash
k6 run wordpress-pressure.js
```

در این حالت متغیرهای محیطی موردنیاز، به‌ویژه `TARGET_URL`، باید از قبل در محیط سیستم تنظیم شده باشند.

### تنظیمات

| متغیر | کاربرد | نمونه |
|---|---|---|
| `TARGET_URL` | آدرس پایه سایت هدف | `https://example.com` |
| `MODE` | روش اجرا: `vus` یا `rps` | `rps` |
| `PATHS` | مسیرهای جداشده با کاما | `/,/blog/,/wp-json/` |
| `SLEEP` | مکث هر VU بین تکرارها، به ثانیه | `1` |
| `VUS` | تعداد کاربران مجازی در حالت VU | `10` |
| `RAMP_UP` | زمان افزایش بار در حالت VU | `1m` |
| `HOLD` | زمان ثابت ماندن بار در حالت VU | `3m` |
| `RAMP_DOWN` | زمان کاهش بار در حالت VU | `1m` |
| `RATE` | تعداد درخواست در هر `TIME_UNIT` در حالت RPS | `100` |
| `DURATION` | مدت اجرای حالت RPS | `3m` |
| `TIME_UNIT` | واحد زمانی نرخ درخواست | `1s` |
| `PRE_ALLOCATED_VUS` | VUهای از پیش تخصیص‌یافته در حالت RPS | `80` |
| `MAX_VUS` | سقف VU در حالت RPS | `250` |

### استفاده اختیاری از پروکسی

حالت پروکسی به‌صورت پیش‌فرض خاموش است. برای فعال‌کردن آن در `.env` بنویسید:

```env
USE_PROXY=true
MAX_PROXY_CANDIDATES=30
MAX_WORKING_PROXIES=5
PROXY_TIMEOUT_SECONDS=5
PROXY_TEST_CONCURRENCY=10
PROXY_CACHE_MINUTES=60
```

هنگام اجرا، `Update-ProxyPool.ps1` فهرست پروکسی‌های HTTP را از دو منبع پیش‌فرض GitHub دریافت می‌کند، ورودی‌های نامعتبر و IPهای خصوصی/رزروشده را حذف می‌کند، نمونه‌ای محدود را از طریق `TARGET_URL` آزمایش می‌کند و پروکسی‌های سالم را در `.proxy-cache/working-proxies.txt` ذخیره می‌کند. در PowerShell 7 تست‌ها با هم‌زمانی محدود اجرا می‌شوند و در Windows PowerShell 5.1 به‌صورت ترتیبی انجام می‌شوند. سپس یک پروکسی سالم به‌صورت تصادفی برای کل فرایند k6 در `HTTP_PROXY` و `HTTPS_PROXY` قرار می‌گیرد. کش محلی در Git ثبت نمی‌شود.

منابع پیش‌فرض:

- [proxifly/free-proxy-list](https://github.com/proxifly/free-proxy-list) — فهرست اعتبارسنجی‌شده و پرتکرار با به‌روزرسانی دوره‌ای
- [TheSpeedX/PROXY-List](https://github.com/TheSpeedX/PROXY-List) — فهرست عمومی فعال و پرکاربرد

برای جایگزین‌کردن منابع، URL فایل‌های خام GitHub را با `;` جدا کنید. به دلایل امنیتی فقط URLهای HTTPS از دامنه `raw.githubusercontent.com` پذیرفته می‌شوند:

```env
PROXY_SOURCE_URLS=https://raw.githubusercontent.com/owner/repo/main/http.txt;https://raw.githubusercontent.com/owner2/repo2/main/proxies.txt
```

برای ساخت یا تازه‌سازی دستی فایل پروکسی‌های سالم:

```powershell
.\Update-ProxyPool.ps1 -TestUrl "https://example.com" -MaxCandidates 30 -MaxWorking 5
```

> [!CAUTION]
> پروکسی عمومی قابل اعتماد یا محرمانه محسوب نمی‌شود. هیچ کوکی ورود، توکن، رمز عبور یا داده حساس را از آن عبور ندهید. فقط هدفی را تست کنید که مجوز صریح آن را دارید. فعال‌کردن پروکسی به معنی توزیع بار میان همه پروکسی‌ها نیست؛ هر اجرای k6 یک پروکسی سالم را برای کل فرایند انتخاب می‌کند. برای استفاده از چند پروکسی، چند اجرای جداگانه لازم است.

برای تغییر موقت یک مقدار بدون ویرایش `.env`:

```powershell
$env:RATE = "25"
$env:DURATION = "1m"
.\run-webava-light.ps1
```

در خروجی k6 به `http_req_failed`، `http_req_duration`، `checks` و `wordpress_5xx_rate` توجه کنید. نرخ را تدریجی بالا ببرید و هم‌زمان CPU، حافظه، PHP-FPM، پایگاه داده، CDN و لاگ‌های سرور را پایش کنید. در تست اولیه از مسیرهای `/wp-login.php` و `/wp-admin/` استفاده نکنید، مگر اینکه هدف مشخص شما ارزیابی حفاظت ورود باشد.

---

## English

A lightweight, configurable [k6](https://grafana.com/docs/k6/latest/) load-testing tool for WordPress websites. It can run with a fixed number of virtual users or a constant request rate and reports response time, failure rate, and server-side 5xx errors.

### Features

- Two execution modes: virtual users (`vus`) and constant request rate (`rps`)
- Configurable ramp-up, steady load, and ramp-down stages in VU mode
- Configurable request rate, duration, and VU capacity in RPS mode
- Random requests across multiple WordPress paths via `PATHS`
- Custom `wordpress_page_duration` response-time metric
- Custom `wordpress_5xx_rate` server-error metric
- Built-in checks for non-5xx and successful 2xx/3xx responses
- Ready-to-use thresholds for failures and p95/p99 latency
- Discarded response bodies to reduce memory use during heavier tests
- PowerShell launcher that automatically loads settings from `.env`
- Optional GitHub-backed public-proxy download, validation, cache, and selection service

### Prerequisites

- Windows and PowerShell for the included launcher; the k6 test itself is cross-platform.
- [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/)
- Git

Install k6 on Windows with winget:

```powershell
winget install GrafanaLabs.k6 --source winget
k6 version
```

Or with Chocolatey:

```powershell
choco install k6
k6 version
```

### Clone, install, and run

```powershell
git clone https://github.com/ZamaniDeveloper/wordpress-load-test.git
cd wordpress-load-test
Copy-Item .env.example .env
```

Edit `.env` and set at least `TARGET_URL` to a website you are authorized to test. Then run:

```powershell
.\run-webava-light.ps1
```

To run k6 directly on any supported operating system:

```bash
k6 run wordpress-pressure.js
```

When running directly, provide the required environment variables—especially `TARGET_URL`—through your shell or environment.

### Configuration

| Variable | Purpose | Example |
|---|---|---|
| `TARGET_URL` | Base URL of the target site | `https://example.com` |
| `MODE` | Execution mode: `vus` or `rps` | `rps` |
| `PATHS` | Comma-separated request paths | `/,/blog/,/wp-json/` |
| `SLEEP` | Delay between VU iterations in seconds | `1` |
| `VUS` | Virtual-user count in VU mode | `10` |
| `RAMP_UP` | VU ramp-up duration | `1m` |
| `HOLD` | Steady-load duration in VU mode | `3m` |
| `RAMP_DOWN` | VU ramp-down duration | `1m` |
| `RATE` | Requests per `TIME_UNIT` in RPS mode | `100` |
| `DURATION` | RPS test duration | `3m` |
| `TIME_UNIT` | Request-rate time unit | `1s` |
| `PRE_ALLOCATED_VUS` | Pre-allocated VUs in RPS mode | `80` |
| `MAX_VUS` | Maximum VUs in RPS mode | `250` |

### Optional proxy mode

Proxy mode is disabled by default. Enable it in `.env`:

```env
USE_PROXY=true
MAX_PROXY_CANDIDATES=30
MAX_WORKING_PROXIES=5
PROXY_TIMEOUT_SECONDS=5
PROXY_TEST_CONCURRENCY=10
PROXY_CACHE_MINUTES=60
```

At startup, `Update-ProxyPool.ps1` downloads HTTP proxy lists from two default GitHub sources, removes malformed entries and private/reserved IP addresses, tests a bounded random sample through `TARGET_URL`, and saves working proxies to `.proxy-cache/working-proxies.txt`. Tests use bounded concurrency on PowerShell 7 and run sequentially on Windows PowerShell 5.1. The launcher then selects one working proxy at random and sets `HTTP_PROXY` and `HTTPS_PROXY` for the entire k6 process. The local cache is excluded from Git.

Default sources:

- [proxifly/free-proxy-list](https://github.com/proxifly/free-proxy-list) — a frequently refreshed, validated proxy list
- [TheSpeedX/PROXY-List](https://github.com/TheSpeedX/PROXY-List) — an active, widely used public list

To replace the sources, separate raw GitHub file URLs with `;`. For safety, only HTTPS URLs hosted on `raw.githubusercontent.com` are accepted:

```env
PROXY_SOURCE_URLS=https://raw.githubusercontent.com/owner/repo/main/http.txt;https://raw.githubusercontent.com/owner2/repo2/main/proxies.txt
```

Build or refresh the working-proxy file manually:

```powershell
.\Update-ProxyPool.ps1 -TestUrl "https://example.com" -MaxCandidates 30 -MaxWorking 5
```

> [!CAUTION]
> Public proxies are neither trusted nor private. Never send login cookies, tokens, passwords, or sensitive data through them, and only test targets you are explicitly authorized to test. Proxy mode does not distribute one k6 run across every proxy: each k6 process selects one working proxy. Run separate k6 processes if you need to use multiple proxies.

Override values for a single run without editing `.env`:

```powershell
$env:RATE = "25"
$env:DURATION = "1m"
.\run-webava-light.ps1
```

Watch `http_req_failed`, `http_req_duration`, `checks`, and `wordpress_5xx_rate` in the k6 summary. Increase load gradually while monitoring CPU, memory, PHP-FPM workers, the database, CDN, and server logs. Avoid `/wp-login.php` and `/wp-admin/` during an initial test unless login-protection testing is your explicit goal.
