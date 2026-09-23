# -*- coding: utf-8 -*-
"""Того · англоязычная копия правовых текстов для сайта.

Само приложение пока говорит только по-русски: в каталоге 1977 ключей
и один язык. Но страницы политики и поддержки читают не только
пользователи — их открывает App Review, и открывает по-английски.
Поэтому английский появляется здесь раньше, чем в интерфейсе.

Русский текст живёт в одном месте — `Togo/Features/Settings/LegalScreens.swift`,
том самом, который человек читает в настройках. Здесь его перевод, и это
вторая копия: ровно то, от чего предостерегает шапка `build_site.py`.
Поэтому копия не оставлена на честное слово. `build_site.py` считает
отпечаток русского текста и сравнивает с `SOURCE_FINGERPRINT` ниже:
правка в LegalScreens.swift без правки перевода валит сборку страниц
с указанием, что именно разошлось. Молча разойтись они не могут.

Когда приложение получит английскую локализацию, эти тексты уедут
в каталог, а файл исчезнет — вместе с отпечатком.
"""

# Отпечаток русского текста, к которому сделан этот перевод.
# Не сходится — `build_site.py` скажет, какой раздел поменялся, и напечатает
# новое значение: перечитать перевод, поправить и вписать сюда.
SOURCE_FINGERPRINT = "b6aa9b6603acda01"

# Подписи вокруг текста: в шаблоне страницы их два языка.
LABELS = {
    "short": "In short",
    "updated": "Updated",
    "other_apps": "other apps",
    "contact": "Contact",
    "privacy": "Privacy Policy",
    "terms": "Terms of Use",
}

DOCUMENTS = {
    "PrivacyPolicyScreen": {
        "file": "privacy.html",
        "title": "Privacy Policy",
        "updated": "25 August 2026",
        "intro": "The short version: the diary lives on your phone. We create no account, we collect no analytics about what you write down, and we pass nothing on to third parties.",
        "sections": [
            ("What is stored, and where", [
                "Your dog’s records — walks, food, water, stools, incidents, training, weight, treatment schedules — are kept in a database on the device and in the storage shared by the app and its widgets.",
                "If iCloud is on, a copy of that database sits in your own private iCloud library. Only you can reach it, along with anyone you have given access to your Apple ID.",
            ]),
            ("What we do not collect", [
                "We collect no advertising identifiers, we use no trackers, and we include no third-party analytics SDKs.",
                "The app never asks for App Tracking Transparency, because there is no tracking to ask about.",
            ]),
            ("What leaves the device", [
                "Subscription purchases are handled by Apple. All we receive from Apple is the fact that a subscription is active — never any payment details.",
                "The vet report, the CSV export and the family invitation go out only when you tap Share yourself, and only to whoever you picked in the system dialog.",
            ]),
            ("Invitations and roles", [
                "An invitation to the shared diary is an iCloud share. Only the person you named in the system Share dialog can open it: nobody who is merely forwarded the address gets in.",
                "The owner sees who is in the diary and can remove anyone. Records already received stay on that person’s phone — iCloud cannot take back what it has shown.",
            ]),
            ("Your rights", [
                "You can export everything to CSV and delete all of your data in Settings → Data and privacy, with no emails and no waiting.",
                "Deleting erases the database on the device. The iCloud copy is removed by the system together with the app’s data.",
            ]),
            ("Children", [
                "The app is not meant for unsupervised use by children under 13. The “helper” role is designed for a child using an adult’s phone.",
            ]),
            ("Get in touch", [
                "\\(Contacts.privacy) — a person answers, usually within two working days.",
            ]),
        ],
    },
    "TermsScreen": {
        "file": "terms.html",
        "title": "Terms of Use",
        "updated": "25 August 2026",
        "intro": "By using Togo you agree to these terms. If something here does not suit you, you can delete the app — your data stays with you.",
        "sections": [
            ("What this app is", [
                "Togo is a dog-care diary. It records what happened, works out the intervals and reminds you.",
                "Togo does not diagnose, does not prescribe doses and is not a medical device.",
            ]),
            ("Subscription", [
                "Togo Pro is an auto-renewing subscription, monthly or yearly. Payment is charged to your Apple ID when you confirm the purchase.",
                "The subscription renews automatically unless it is cancelled at least 24 hours before the end of the current period.",
                "You can manage the subscription and turn auto-renewal off in your Apple ID settings after the purchase.",
                "Any unused part of a free trial is forfeited when a subscription is bought.",
            ]),
            ("What stays free", [
                "The fasting window, double-dose protection, “asked to go”, “refused food” and the warning against punishing a dog after an accident are free for good and are not part of the subscription.",
            ]),
            ("Liability", [
                "Decisions about your dog’s health are made by you and your vet. The app only shows what you put into it yourself.",
                "We are not liable for the consequences of decisions taken on the basis of records in the app.",
            ]),
            ("Ending it", [
                "You can stop using the app at any time. We may end support for a version, saying so in the “What’s new” section.",
            ]),
        ],
    },
    "MedicalDisclaimerScreen": {
        "file": "medical.html",
        "title": "Not a medical device",
        "updated": "25 August 2026",
        "intro": "Togo helps you keep records. It does not diagnose and it does not prescribe treatment.",
        "sections": [
            ("What the app does", [
                "It records what you marked down, and works out the intervals between entries.",
                "It reminds you about a dose on schedule and shows the fasting window.",
                "It builds the vet report out of what you have already noted — without a single “fill this in for the vet” field.",
            ]),
            ("What the app does not do", [
                "It does not interpret test results, does not pick medicines and does not adjust doses.",
                "It does not replace a visit to the vet. The “needs to go out” verdict is a statistic drawn from your own entries, not a conclusion.",
            ]),
            ("When to go to the vet rather than to the app", [
                "Blood in the stool or in vomit. Repeated vomiting. Refusing water.",
                "Barking or restlessness at the door that has appeared suddenly — that may not be behaviour but discomfort.",
                "Any situation where you are unsure. The app does not know better than you and your vet.",
            ]),
        ],
    },
    "AcknowledgementsScreen": {
        "file": "built-with.html",
        "title": "What it’s built from",
        "updated": "25 August 2026",
        "intro": "Togo is built on Apple’s own frameworks, with no third-party dependencies at all: SwiftUI, SwiftData, StoreKit 2, WidgetKit, ActivityKit, UserNotifications, Charts.",
        "sections": [
            ("Icons", [
                "Every interface icon is an SF Symbol, Apple’s system library. The app carries no bitmap icons of its own.",
            ]),
            ("Typeface", [
                "San Francisco, the system typeface. It is already on the device, it handles Dynamic Type, and it needs no licence.",
            ]),
            ("Thank you", [
                "To the dog trainers who took the mock-up apart and explained why counting treats gets in the way of learning.",
                "To Stitch, for putting up with every version of this app.",
            ]),
        ],
    },
}

# Страница поддержки не выводится из приложения: в интерфейсе такого экрана
# нет, вопросы собраны из писем. Русский её вариант — в `build_site.py`.
SUPPORT = {
    "file": "support.html",
    "title": "Support",
    "page_title": "Support — Togo, a dog diary",
    "description": "How to reach the author of Togo, and answers to common questions: why the verdict says “not sure”, where the Health tab went, how to get your records out.",
    "updated": "A person answers, usually within two working days.",
    "body": """
<div class="card">
  <h2>Write to us</h2>
  <p><a href="mailto:{support}?subject=Togo">{support}</a></p>
  <p>If you are writing about a bug, include the version and build — they are
  in Settings → Version, where you can select and copy them. And your phone
  model with its iOS version.</p>
  <p>If something in the app is getting in the way of looking after your dog,
  write straight away. That matters more than new features.</p>
</div>

<h2>Common questions</h2>

<h3>Why does the verdict say “not sure”?</h3>
<p>It needs three or four days of records to learn your dog’s intervals. Until
then it admits it does not know rather than inventing an answer. The “Taking
him out” button stays first in every case: the app does not know better
than you.</p>

<h3>Where is the Health tab?</h3>
<p>It arrives with a course of treatment and leaves with it: you switch it on
in the dog’s profile and off with “Course finished” at the bottom of Health.
The records stay in the history and in the vet report.</p>

<h3>Two people logged the same thing</h3>
<p>If two people log the same thing within 20 minutes, the app shows both of
them a merge card. It never silently overwrites someone else’s entry.</p>

<h3>How do I get my records out?</h3>
<p>Settings → Data and privacy — export to CSV and delete everything, with no
emails and no waiting. The CSV opens in Numbers and Excel.</p>

<h2>This app is not a medical device</h2>
<p>Togo does not diagnose and does not prescribe doses. Decisions about your
dog’s health are made by you and your vet; the app shows what you put into
it yourself.</p>
""",
    "footer": """
  <p><a href="privacy.html">Privacy Policy</a> ·
     <a href="terms.html">Terms of Use</a> ·
     <a href="../../en/index.html">other apps</a></p>
""",
}
