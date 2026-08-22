# راهنمای فعال و غیرفعال‌کردن حساب کاربری در Linux

<div dir="rtl" align="right">

این راهنما برای **غیرفعال‌کردن موقت یک کاربر لینوکس بدون حذف حساب، Home Directory و فایل‌های او** نوشته شده است.

سناریوی اصلی این است که کاربر فعلاً امکان ورود به سرور را نداشته باشد، اما اطلاعات و مالکیت فایل‌های او حفظ شود تا در صورت نیاز بتوان حساب را دوباره فعال کرد.

> **نکته مهم:** حذف کاربر (`userdel`) برای این سناریو توصیه نمی‌شود.

---

## 1. تعریف نام کاربر

در مثال‌های این راهنما از متغیر `USERNAME` استفاده شده است.

برای نمونه:

</div>

```bash
USERNAME="masoud"
```

<div dir="rtl" align="right">

قبل از انجام هر تغییری، وجود کاربر را بررسی کنید:

</div>

```bash
id "$USERNAME"
```

<div dir="rtl" align="right">

---

# غیرفعال‌کردن حساب کاربری

## 2. Lock کردن Password

دستور زیر Password حساب را Lock می‌کند:

</div>

```bash
sudo usermod -L "$USERNAME"
```

<div dir="rtl" align="right">

یا:

</div>

```bash
sudo passwd -l "$USERNAME"
```

<div dir="rtl" align="right">

### این دستور چه کاری انجام می‌دهد؟

Password Hash کاربر در `/etc/shadow` به حالت Lock می‌رود و کاربر دیگر نمی‌تواند با Password معمولی Login کند.

> **مهم:** Lock کردن Password به‌تنهایی لزوماً Login با SSH Key یا سایر روش‌های Authentication را مسدود نمی‌کند.

به همین دلیل برای غیرفعال‌سازی کامل‌تر، Account Expiration نیز توصیه می‌شود.

---

## 3. Expire کردن حساب

برای Expire کردن حساب:

</div>

```bash
sudo chage -E 0 "$USERNAME"
```

<div dir="rtl" align="right">

این کار باعث می‌شود حساب از نظر سیستم منقضی شده و Login جدید برای آن مجاز نباشد.

برای مشاهده وضعیت Expiration:

</div>

```bash
sudo chage -l "$USERNAME"
```

<div dir="rtl" align="right">

---

## 4. غیرفعال‌کردن Interactive Shell

اگر می‌خواهید کاربر Shell تعاملی نیز نداشته باشد، Shell حساب را به `nologin` تغییر دهید.

ابتدا محل `nologin` را بررسی کنید:

</div>

```bash
command -v nologin
```

<div dir="rtl" align="right">

در Ubuntu/Debian معمولاً مسیر زیر است:

</div>

```bash
/usr/sbin/nologin
```

<div dir="rtl" align="right">

سپس:

</div>

```bash
sudo usermod -s /usr/sbin/nologin "$USERNAME"
```

<div dir="rtl" align="right">

برای بررسی:

</div>

```bash
getent passwd "$USERNAME"
```

<div dir="rtl" align="right">

> تغییر Shell برای همه سناریوها الزامی نیست. اگر حساب متعلق به یک Service Account است، قبل از تغییر Shell بررسی کنید که سرویس یا اسکریپتی به Shell آن وابسته نباشد.

---

# قطع Sessionهای فعال

## 5. بررسی Sessionهای فعلی

غیرفعال‌کردن حساب، Sessionهایی که **از قبل باز هستند** را الزاماً قطع نمی‌کند.

ابتدا Sessionهای کاربر را بررسی کنید:

</div>

```bash
who
```

```bash
w
```

<div dir="rtl" align="right">

در سیستم‌های دارای systemd می‌توانید از این دستور نیز استفاده کنید:

</div>

```bash
loginctl list-sessions
```

<div dir="rtl" align="right">

---

## 6. قطع Sessionهای کاربر

در سیستم‌های systemd:

</div>

```bash
sudo loginctl terminate-user "$USERNAME"
```

<div dir="rtl" align="right">

روش مستقیم‌تر:

</div>

```bash
sudo pkill -KILL -u "$USERNAME"
```

<div dir="rtl" align="right">

> **هشدار:**  
> `pkill -KILL -u USERNAME` تمام Processهای متعلق به UID کاربر را متوقف می‌کند.  
> اگر کاربر Service، Job، Script، Container یا Process مهمی اجرا کرده باشد، این دستور ممکن است باعث اختلال سرویس شود.

قبل از اجرای آن بهتر است Processهای کاربر را بررسی کنید:

</div>

```bash
ps -u "$USERNAME" -f
```

<div dir="rtl" align="right">

---

# بررسی وضعیت حساب

## 7. بررسی Password Status

</div>

```bash
sudo passwd -S "$USERNAME"
```

<div dir="rtl" align="right">

خروجی ممکن است مشابه زیر باشد:

</div>

```text
masoud L ...
```

<div dir="rtl" align="right">

حرف `L` معمولاً نشان‌دهنده Locked بودن Password است.

---

## 8. بررسی Account Expiration

</div>

```bash
sudo chage -l "$USERNAME"
```

<div dir="rtl" align="right">

---

## 9. بررسی Shell

</div>

```bash
getent passwd "$USERNAME"
```

<div dir="rtl" align="right">

مثال:

</div>

```text
masoud:x:1001:1001::/home/masoud:/usr/sbin/nologin
```

<div dir="rtl" align="right">

---

# روش پیشنهادی برای غیرفعال‌سازی موقت

برای یک حساب کاربری عادی که می‌خواهید بدون حذف اطلاعات غیرفعال شود:

</div>

```bash
USERNAME="masoud"

sudo usermod -L "$USERNAME"
sudo chage -E 0 "$USERNAME"
```

<div dir="rtl" align="right">

در صورت نیاز به جلوگیری از Shell تعاملی:

</div>

```bash
sudo usermod -s /usr/sbin/nologin "$USERNAME"
```

<div dir="rtl" align="right">

اگر لازم است Sessionهای فعلی نیز قطع شوند:

</div>

```bash
sudo loginctl terminate-user "$USERNAME"
```

<div dir="rtl" align="right">

یا پس از بررسی Processها:

</div>

```bash
sudo pkill -KILL -u "$USERNAME"
```

<div dir="rtl" align="right">

---

# فعال‌کردن مجدد حساب

## 10. Unlock کردن Password

</div>

```bash
sudo usermod -U "$USERNAME"
```

<div dir="rtl" align="right">

یا:

</div>

```bash
sudo passwd -u "$USERNAME"
```

<div dir="rtl" align="right">

---

## 11. حذف Account Expiration

</div>

```bash
sudo chage -E -1 "$USERNAME"
```

<div dir="rtl" align="right">

---

## 12. بازگرداندن Shell

اگر Shell قبلی کاربر `/bin/bash` بوده است:

</div>

```bash
sudo usermod -s /bin/bash "$USERNAME"
```

<div dir="rtl" align="right">

> اگر Shell قبلی چیز دیگری بوده، همان Shell قبلی را بازگردانید.

برای بررسی Shellهای معتبر سیستم:

</div>

```bash
cat /etc/shells
```

<div dir="rtl" align="right">

---

# فعال‌سازی مجدد کامل

</div>

```bash
USERNAME="masoud"

sudo usermod -U "$USERNAME"
sudo chage -E -1 "$USERNAME"
sudo usermod -s /bin/bash "$USERNAME"
```

<div dir="rtl" align="right">

سپس وضعیت را بررسی کنید:

</div>

```bash
sudo passwd -S "$USERNAME"
sudo chage -l "$USERNAME"
getent passwd "$USERNAME"
```

<div dir="rtl" align="right">

---

# وضعیت Home Directory و فایل‌ها

غیرفعال‌کردن حساب با روش‌های این راهنما موارد زیر را حذف نمی‌کند:

- Home Directory کاربر
- فایل‌ها و پوشه‌های کاربر
- UID و GID
- Group Membership
- Ownership فایل‌ها
- SSH Keys
- Cron Jobs
- فایل‌های Configuration

برای نمونه:

</div>

```bash
ls -ld "/home/$USERNAME"
```

<div dir="rtl" align="right">

بنابراین Account Disable با Account Delete متفاوت است.

---

# نکات امنیتی مهم

## SSH Key

دستور زیر:

</div>

```bash
sudo usermod -L "$USERNAME"
```

<div dir="rtl" align="right">

فقط Password را Lock می‌کند و نباید به‌تنهایی به‌عنوان روش قطعی برای جلوگیری از همه روش‌های Login در نظر گرفته شود.

ترکیب زیر برای یک حساب انسانی معمولاً مطمئن‌تر است:

</div>

```bash
sudo usermod -L "$USERNAME"
sudo chage -E 0 "$USERNAME"
```

<div dir="rtl" align="right">

و در صورت نیاز:

</div>

```bash
sudo usermod -s /usr/sbin/nologin "$USERNAME"
```

<div dir="rtl" align="right">

---

## Service Accountها

قبل از Disable کردن یک حساب بررسی کنید که Service یا Application مهمی با UID آن اجرا نشده باشد:

</div>

```bash
ps -u "$USERNAME" -f
```

<div dir="rtl" align="right">

همچنین می‌توانید مالکیت فایل‌ها را بررسی کنید:

</div>

```bash
sudo find / -xdev -user "$USERNAME" -ls 2>/dev/null
```

<div dir="rtl" align="right">

---

# بررسی سریع قبل از Disable

</div>

```bash
USERNAME="masoud"

id "$USERNAME"
getent passwd "$USERNAME"
ps -u "$USERNAME" -f
sudo passwd -S "$USERNAME"
sudo chage -l "$USERNAME"
```

<div dir="rtl" align="right">

---

# خلاصه دستورات

| عملیات | دستور |
|---|---|
| Lock Password | `sudo usermod -L USERNAME` |
| Unlock Password | `sudo usermod -U USERNAME` |
| Expire Account | `sudo chage -E 0 USERNAME` |
| Remove Expiration | `sudo chage -E -1 USERNAME` |
| Disable Shell | `sudo usermod -s /usr/sbin/nologin USERNAME` |
| Restore Bash | `sudo usermod -s /bin/bash USERNAME` |
| View Password Status | `sudo passwd -S USERNAME` |
| View Account Aging | `sudo chage -l USERNAME` |
| View User Processes | `ps -u USERNAME -f` |
| Terminate systemd User Sessions | `sudo loginctl terminate-user USERNAME` |
| Kill All User Processes | `sudo pkill -KILL -u USERNAME` |

---

# پیشنهاد عملی

برای **غیرفعال‌کردن موقت یک کاربر انسانی** بدون حذف اطلاعات، معمولاً این دو دستور کافی و مناسب هستند:

</div>

```bash
sudo usermod -L "$USERNAME"
sudo chage -E 0 "$USERNAME"
```

<div dir="rtl" align="right">

اگر می‌خواهید امکان Interactive Shell هم وجود نداشته باشد:

</div>

```bash
sudo usermod -s /usr/sbin/nologin "$USERNAME"
```

<div dir="rtl" align="right">

حذف کاربر با `userdel` فقط زمانی منطقی است که واقعاً قصد حذف Account را داشته باشید و سیاست نگهداری اطلاعات سازمان اجازه آن را بدهد.

</div>


<div dir="rtl" align="right">

# شناسایی کاربران غیرفعال

در Linux یک وضعیت واحد به نام `Disabled User` وجود ندارد. یک حساب ممکن است به یکی یا چند روش زیر غیرفعال شده باشد:

- Password حساب Lock شده باشد.
- Account منقضی (Expired) شده باشد.
- Login Shell روی `nologin` یا `false` تنظیم شده باشد.
- ترکیبی از موارد بالا اعمال شده باشد.

به همین دلیل برای شناسایی دقیق کاربران غیرفعال باید چند وضعیت را هم‌زمان بررسی کرد.

---

## مشاهده حساب‌هایی که Password آن‌ها Lock شده است

</div>

```bash
sudo passwd -Sa | awk '$2=="L"'
```

<div dir="rtl" align="right">

برای نمایش فقط نام کاربران:

</div>

```bash
sudo passwd -Sa | awk '$2=="L" {print $1}'
```

<div dir="rtl" align="right">

> این خروجی ممکن است شامل System Accountها نیز باشد.

---

## مشاهده کاربران عادی با Password Lock شده

در بسیاری از توزیع‌های Linux، کاربران عادی معمولاً UID برابر یا بزرگ‌تر از `1000` دارند.

</div>

```bash
getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' |
while read user; do
    status=$(sudo passwd -S "$user" 2>/dev/null | awk '{print $2}')
    if [ "$status" = "L" ]; then
        echo "$user"
    fi
done
```

<div dir="rtl" align="right">

---

## مشاهده حساب‌هایی که Shell آن‌ها غیرفعال است

برای پیدا کردن حساب‌هایی که Login Shell آن‌ها روی `nologin` یا `false` تنظیم شده است:

</div>

```bash
getent passwd | awk -F: '$7 ~ /(nologin|false)$/ {print $1, $3, $7}'
```

<div dir="rtl" align="right">

مثال:

</div>

```text
masoud 1001 /usr/sbin/nologin
```

<div dir="rtl" align="right">

---

## بررسی Expiration یک کاربر مشخص

</div>

```bash
sudo chage -l masoud
```

<div dir="rtl" align="right">

به مقدار زیر توجه کنید:

</div>

```text
Account expires : ...
```

<div dir="rtl" align="right">

---

## نمایش وضعیت کامل کاربران عادی

دستور زیر وضعیت Password، تاریخ Expiration و Shell تمام کاربران عادی را در یک خروجی نمایش می‌دهد:

</div>

```bash
getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' |
while read user; do
    status=$(sudo passwd -S "$user" 2>/dev/null | awk '{print $2}')
    expire=$(sudo chage -l "$user" 2>/dev/null | awk -F': ' '/Account expires/{print $2}')
    shell=$(getent passwd "$user" | cut -d: -f7)

    printf "%-20s Password=%-3s Expire=%-15s Shell=%s\n" \
        "$user" "$status" "$expire" "$shell"
done
```

<div dir="rtl" align="right">

نمونه خروجی:

</div>

```text
reza                 Password=P   Expire=never           Shell=/bin/bash
masoud               Password=L   Expire=Jan 01, 1970    Shell=/usr/sbin/nologin
ali                   Password=P   Expire=never           Shell=/bin/bash
```

<div dir="rtl" align="right">

در این مثال:

- `P` یعنی Password قابل استفاده است.
- `L` یعنی Password Lock شده است.
- `Expire=never` یعنی حساب منقضی نشده است.
- `/usr/sbin/nologin` یعنی Login تعاملی از طریق Shell غیرفعال است.

---

## وضعیت پیشنهادی برای تشخیص یک حساب کاملاً غیرفعال

اگر طبق روش این Runbook حساب را غیرفعال کرده باشید، معمولاً این سه وضعیت را خواهید دید:

</div>

```text
Password=L
Account expired
Shell=/usr/sbin/nologin
```

<div dir="rtl" align="right">

البته اگر فقط از روش پیشنهادی `Lock + Expire` استفاده کرده باشید، ممکن است Shell همچنان `/bin/bash` باقی مانده باشد.

---
</div>
