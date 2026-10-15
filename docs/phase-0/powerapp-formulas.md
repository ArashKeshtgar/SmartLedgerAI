# فرمول‌های تازهٔ Power App (راه‌حل الف) — فقط برای کپی staging

> **اگر Power Apps پروسیجر را نشناخت** (خطای `unknown or unsupported function`): به‌جای این فایل، راه‌حل ب+ را در [`findings.md`](findings.md) ببینید؛ آن به فرمول‌های اپ دست نمی‌زند.

این فرمول‌ها جای فرمول‌های فعلی چهار دکمه را می‌گیرند. فقط در **کپی** اپ که به `FinancePowerApp-staging` وصل است
عوض شوند، نه در اپ اصلی.

## قبل از شروع (یک بار)

1. اسکریپت [`sql/phase0/002_expense_writes_via_procedures.sql`](../../sql/phase0/002_expense_writes_via_procedures.sql)
   روی staging اجرا شده باشد.
2. در کپی اپ: **Data** ← **Add data** ← **SQL Server** ← همان connection staging ← زبانهٔ **Stored procedures**.
   این چهار را تیک بزنید و **Connect**: `sp_InsertExpense`، `sp_AssignExpensePeriod`، `sp_ApproveExpense`،
   `sp_RejectExpense`.
3. **اسم connection:** در فرمول‌های زیر به‌جای `FinanceSQL` اسمی را بگذارید که اپ شما نشان می‌دهد. راه پیدا کردنش: در
   نوار فرمول اسم connection را تایپ کنید و یک نقطه بگذارید؛ فهرست پروسیجرها با اسمی مثل `dbosp_InsertExpense` باز
   می‌شود. اگر اسم کمی فرق داشت، همانی را بردارید که فهرست نشان می‌دهد.

## ۱. دکمهٔ Submit expense — خاصیت `OnSelect`

```
IfError(
    FinanceSQL.dbosp_InsertExpense(
        {
            Amount: Value(uiAmountTxt.Text),
            Category: uiCategorydd.Selected.Value,
            ExpenseDate: uiDatedp.SelectedDate,
            Vendor: uiVendorTxt.Text,
            Description: uiDescriptiontxt.Text,
            TaxAmount: Round(Value(uiAmountTxt.Text) * 0.13, 2)
        }
    ),
    Notify("Error saving expense: " & FirstError.Message, NotificationType.Error),
    Refresh(Expenses);
    Refresh(vw_ExpenseList);
    Reset(uiAmountTxt);
    Reset(uiVendorTxt);
    Reset(uiDescriptiontxt);
    Notify("Expense submitted.", NotificationType.Success)
)
```

**فرق مهم:** وضعیت را دیگر لیست کشویی `uiStatusdd` تعیین نمی‌کند. هر هزینهٔ تازه با وضعیت **Pending** ثبت می‌شود. تا
امروز هر کسی می‌توانست هزینه را از همان اول «Approved» ثبت کند، یعنی بدون تأیید و بدون ثبت اسم تأییدکننده. این یک
حفرهٔ کنترلی دیگر بود. `uiStatusdd` را پنهان کنید (`Visible` = `false`) یا از صفحه بردارید.

اگر Power Apps برای `PeriodId` یا `CategoryId` هم مقدار خواست، `PeriodId: Blank(), CategoryId: Blank()` را اضافه کنید.

## ۲. دکمهٔ AssignPeriod — خاصیت `OnSelect`

```
IfError(
    FinanceSQL.dbosp_AssignExpensePeriod(
        {
            ExpenseId: varSelectedExpense.ExpenseId,
            PeriodId: uiPeriodcmb.Selected.PeriodId
        }
    ),
    Notify("Failed: " & FirstError.Message, NotificationType.Error),
    Refresh(Expenses);
    Set(varSelectedExpense, LookUp(Expenses, ExpenseId = varSelectedExpense.ExpenseId));
    Notify("Fiscal period assigned.", NotificationType.Success)
)
```

## ۳. دکمهٔ Approve — خاصیت `OnSelect`

```
IfError(
    FinanceSQL.dbosp_ApproveExpense(
        {
            ExpenseId: varSelectedExpense.ExpenseId,
            ApprovedBy: User().FullName
        }
    ),
    Notify("Failed to approve: " & FirstError.Message, NotificationType.Error),
    Refresh(Expenses);
    Set(varSelectedExpense, LookUp(Expenses, ExpenseId = varSelectedExpense.ExpenseId));
    Notify("Expense approved.", NotificationType.Success)
)
```

تاریخ تأیید را حالا خود دیتابیس می‌گذارد، نه گوشی یا کامپیوتر کاربر. در تست نگاه کنید ساعتی که اپ نشان می‌دهد درست
است؛ اگر چند ساعت جلو یا عقب بود، بگویید.

## ۴. دکمهٔ Reject — خاصیت `OnSelect`

```
IfError(
    FinanceSQL.dbosp_RejectExpense(
        {
            ExpenseId: varSelectedExpense.ExpenseId,
            RejectedBy: User().FullName
        }
    ),
    Notify("Failed to reject: " & FirstError.Message, NotificationType.Error),
    Refresh(Expenses);
    Set(varSelectedExpense, LookUp(Expenses, ExpenseId = varSelectedExpense.ExpenseId));
    Notify("Expense rejected.", NotificationType.Success)
)
```

پیام‌های فرمول فعلی Reject اشتباهاً «approve» می‌گفتند؛ اینجا درست شده‌اند. اسم ردکننده مثل امروز در `ApprovedBy`
ذخیره می‌شود. هزینهٔ تأییدشده را دیگر نمی‌شود رد کرد.

## بقیهٔ دکمه‌ها

**Close Month**، **Export CSV** و **Annual summary** دست نمی‌خورند. جدول ماه‌ها (`AccountingPeriods`) تریگر ندارد،
پس `Patch` روی آن کار می‌کند.

## آزمون روی staging

| کار | ماه باز | ماه بسته |
|---|---|---|
| Submit expense | ثبت می‌شود، با وضعیت Pending | — (هزینهٔ تازه هنوز ماه ندارد) |
| AssignPeriod | ماه عوض می‌شود | پیام «Accounting period is closed» |
| Approve | Approved، با اسم شما | پیام «Accounting period is closed» |
| Reject | Rejected، با اسم شما | پیام «Accounting period is closed» |
| Reject روی هزینهٔ تأییدشده | پیام «An approved expense cannot be rejected» | — |

برای ستون «ماه بسته»: یک هزینه را به ماهی بدهید، آن ماه را با Close Month ببندید، بعد سه کار را روی همان هزینه
امتحان کنید. **ماه را روی staging ببندید، نه روی اپ اصلی.**
