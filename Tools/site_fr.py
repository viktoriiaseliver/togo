# -*- coding: utf-8 -*-
"""Того · франкоязычная копия правовых текстов для сайта.

Зачем файл появился: у приложения французский живой — 2029 строк из 2123
в каталоге, — и французская карточка витрины лежит в
`fastlane/metadata/fr-FR/`. А правовых страниц на французском не было:
замер 23.09.2026 показал `404` на `togo/fr/terms.html` и
`togo/fr/privacy.html`. Развилка по языку браузера знает два языка, `ru`
и `en`, и всё остальное роняет в английский. Практически это француз,
который жмёт «Conditions d'utilisation» под подпиской и читает условия
по-английски. Для автопродляемой подписки ссылка обязана работать, и на
языке витрины.

Это **третья копия** русского текста — ровно то, от чего предостерегает
шапка `build_site.py`, и та же плата, которую уже платит `site_en.py`.
Поэтому копия сторожится так же: `SOURCE_FINGERPRINT` ниже — отпечаток
русского текста, к которому сделан перевод. Правка `LegalScreens.swift`
без правки перевода обязана валить сборку страниц, а не расходиться
молча.

**Файл пока не подключён.** `build_site.py:47` держит `LANGS = ("en", "ru")`,
и французского в генераторе нет. Подключение — правка генератора, она
за сессией Togo: одновременная правка одного файла двумя руками стоит
дороже, чем ожидание. Чтобы подключить, нужно добавить "fr" в `LANGS`,
импортировать `site_fr` рядом с `site_en` и сверять отпечаток по обоим.

Термины взяты не с русского, а из каталога приложения — те самые слова,
которые француз уже видит на экране: «fenêtre à jeun», «protection contre
la double dose», «Données et confidentialité», «Je le sors», «Pas clair»,
«Traitement terminé», «Matrice de généralisation». Витрина, интерфейс и
правовые страницы обязаны говорить одним словарём.

Обращение — на «tu», как в интерфейсе и в карточке витрины. Страница на
«vous» при приложении на «tu» обещает другой продукт.

Состав документов — тот же, что у английского: на сайт уходят только
политика и условия. Дисклеймер «не медицинское устройство» и «Открытый
код» живут только в приложении и не публикуются ни на одном языке —
асимметрия не моя, я её лишь повторила, чтобы французский не разошёлся
с английским.
"""

# Отпечаток русского текста, к которому сделан этот перевод.
# Значение то же, что в `site_en.py`: источник один — `LegalScreens.swift`.
# Не сходится — `build_site.py` скажет, какой раздел поменялся.
SOURCE_FINGERPRINT = "b6aa9b6603acda01"

# Подписи вокруг текста: в шаблоне страницы их два языка.
LABELS = {
    "short": "En bref",
    "updated": "Mis à jour",
    "other_apps": "autres applications",
    "contact": "Contact",
    "privacy": "Politique de confidentialité",
    "terms": "Conditions d'utilisation",
}

DOCUMENTS = {
    "PrivacyPolicyScreen": {
        "file": "privacy.html",
        "title": "Politique de confidentialité",
        "updated": "25 août 2026",
        "intro": "La version courte : le carnet vit sur ton téléphone. Nous ne créons pas de compte, nous ne collectons aucune statistique sur ce que tu notes, et nous ne transmettons rien à des tiers.",
        "sections": [
            ("Ce qui est conservé, et où", [
                "Les entrées sur ton chien — sorties, repas, eau, selles, incidents, séances, poids, traitements — sont conservées dans une base sur l'appareil et dans le stockage partagé entre l'app et ses widgets.",
                "Si iCloud est activé, une copie de cette base se trouve dans ta bibliothèque iCloud privée. Toi seul y as accès, ainsi que les personnes à qui tu as donné accès à ton compte Apple.",
            ]),
            ("Ce que nous ne collectons pas", [
                "Nous ne collectons pas d'identifiants publicitaires, nous n'utilisons pas de traceurs et nous n'intégrons aucun SDK d'analyse tiers.",
                "L'app ne demande jamais l'autorisation App Tracking Transparency, parce qu'il n'y a aucun suivi à autoriser.",
            ]),
            ("Ce qui sort de l'appareil", [
                "L'achat de l'abonnement est traité par Apple. Tout ce que nous recevons d'Apple, c'est le fait qu'un abonnement est actif — jamais de données de paiement.",
                "Le compte rendu pour le vétérinaire, l'export CSV et l'invitation au carnet partagé ne partent que lorsque tu appuies toi-même sur « Partager », et uniquement vers la personne que tu as choisie dans la fenêtre système.",
            ]),
            ("Invitations et rôles", [
                "Une invitation au carnet partagé est un partage iCloud. Seule la personne que tu as nommée dans la fenêtre système « Partager » peut l'ouvrir : personne ne peut entrer avec une adresse transférée.",
                "Le propriétaire voit qui est dans le carnet et peut retirer n'importe qui. Les entrées déjà reçues restent sur le téléphone de celui qui les a reçues : iCloud ne sait pas reprendre ce qu'il a montré.",
            ]),
            ("Tes droits", [
                "Tu peux tout exporter en CSV et supprimer toutes tes données dans « Réglages → Données et confidentialité », sans courrier et sans attente.",
                "La suppression efface la base sur l'appareil. La copie dans iCloud est supprimée par le système en même temps que les données de l'app.",
            ]),
            ("Enfants", [
                "L'app n'est pas destinée à un usage autonome par des enfants de moins de 13 ans. Le rôle « assistant » est prévu pour un enfant qui utilise le téléphone d'un adulte.",
            ]),
            ("Nous contacter", [
                "\\(Contacts.privacy) — une personne répond, en général sous deux jours ouvrés.",
            ]),
        ],
    },
    "TermsScreen": {
        "file": "terms.html",
        "title": "Conditions d'utilisation",
        "updated": "25 août 2026",
        "intro": "En utilisant Togo, tu acceptes ces conditions. Si quelque chose ne te convient pas, tu peux supprimer l'app — tes données restent chez toi.",
        "sections": [
            ("Ce qu'est cette application", [
                "Togo est un journal de soins du chien. Il note, calcule les intervalles et rappelle.",
                "Togo ne pose pas de diagnostic, ne prescrit pas de dose et n'est pas un dispositif médical.",
            ]),
            ("Abonnement", [
                "Togo Pro est un abonnement à renouvellement automatique, mensuel ou annuel. Le paiement est débité sur ton compte Apple à la confirmation de l'achat.",
                "L'abonnement se renouvelle automatiquement, sauf s'il est annulé au moins 24 heures avant la fin de la période en cours.",
                "Tu peux gérer l'abonnement et désactiver le renouvellement automatique dans les réglages de ton compte Apple après l'achat.",
                "La partie non utilisée de l'essai gratuit est perdue à l'achat d'un abonnement.",
            ]),
            ("Ce qui reste gratuit", [
                "La fenêtre à jeun, la protection contre la double dose, « comment il a demandé », « n'a pas pris la friandise » et le rappel de ne pas punir après un pipi à la maison sont gratuits pour toujours et ne font pas partie de l'abonnement.",
            ]),
            ("Responsabilité", [
                "Les décisions sur la santé du chien, c'est toi et ton vétérinaire qui les prenez. L'app ne fait que montrer ce que vous y avez vous-mêmes noté.",
                "Nous ne répondons pas des conséquences de décisions prises sur la base des entrées de l'app.",
            ]),
            ("Fin d'utilisation", [
                "Tu peux cesser d'utiliser l'app à tout moment. Nous pouvons arrêter de prendre en charge une version, en prévenant dans la rubrique « Nouveautés ».",
            ]),
        ],
    },
    "MedicalDisclaimerScreen": {
        "file": "medical.html",
        "title": "Pas un dispositif médical",
        "updated": "25 août 2026",
        "intro": "Togo aide à tenir des notes. Il ne pose pas de diagnostic et ne prescrit pas de traitement.",
        "sections": [
            ("Ce que l'app fait", [
                "Elle note ce que tu as coché et calcule les intervalles entre les entrées.",
                "Elle rappelle la dose selon l'horaire et montre la fenêtre à jeun.",
                "Elle assemble le compte rendu pour le vétérinaire à partir de ce qui est déjà noté — sans un seul champ « à remplir pour le vétérinaire ».",
            ]),
            ("Ce que l'app ne fait pas", [
                "Elle n'interprète pas les analyses, ne choisit pas les médicaments et n'ajuste pas les doses.",
                "Elle ne remplace pas une visite chez le vétérinaire. Le verdict « envie de sortir » est une statistique sur tes propres entrées, pas une conclusion.",
            ]),
            ("Quand aller chez le vétérinaire plutôt que dans l'app", [
                "Du sang dans les selles ou les vomissements. Des vomissements répétés. Un refus de boire.",
                "Un aboiement ou une agitation devant la porte apparus brutalement — ce n'est peut-être pas du comportement, mais de l'inconfort.",
                "Toute situation où tu as un doute. L'app ne sait pas mieux que toi et ton vétérinaire.",
            ]),
        ],
    },
}

# Страница поддержки не выводится из приложения: в интерфейсе такого экрана
# нет, вопросы собраны из писем. Русский её вариант — в `build_site.py`,
# английский — в `site_en.py`.
SUPPORT = {
    "file": "support.html",
    "title": "Assistance",
    "page_title": "Assistance — Togo, le carnet du chien",
    "description": "Comment joindre l'auteur de Togo, et les réponses aux questions fréquentes : pourquoi le verdict dit « Pas clair », où est passé l'onglet Santé, comment récupérer ses entrées.",
    "updated": "Une personne répond, en général sous deux jours ouvrés.",
    "body": """
<div class="card">
  <h2>Écris-nous</h2>
  <p><a href="mailto:{support}?subject=Togo">{support}</a></p>
  <p>Si tu écris à propos d'un bug, indique la version et le build — ils sont
  dans Réglages → Version, où tu peux les sélectionner et les copier. Ainsi
  que ton modèle de téléphone et sa version d'iOS.</p>
  <p>Si quelque chose dans l'app te gêne pour t'occuper de ton chien, écris
  tout de suite. Ça compte plus que les nouvelles fonctions.</p>
</div>

<h2>Questions fréquentes</h2>

<h3>Pourquoi le verdict dit « Pas clair »&#8239;?</h3>
<p>Il lui faut trois ou quatre jours d'entrées pour apprendre les intervalles
de ton chien. En attendant, il reconnaît qu'il ne sait pas au lieu d'inventer
une réponse. Le bouton « Je le sors » reste en premier dans tous les cas :
l'app ne sait pas mieux que toi.</p>

<h3>Où est l'onglet « Santé »&#8239;?</h3>
<p>Il arrive avec un traitement et repart avec lui : tu l'actives dans le
profil du chien et tu le désactives avec « Traitement terminé », en bas de
Santé. Les entrées restent dans l'historique et dans le compte rendu pour le
vétérinaire.</p>

<h3>Deux personnes ont noté la même chose</h3>
<p>Si deux personnes notent la même chose à moins de 20 minutes d'intervalle,
l'app leur montre à toutes les deux une carte de fusion. Elle n'écrase jamais
en silence l'entrée de quelqu'un d'autre.</p>

<h3>Comment récupérer mes entrées&#8239;?</h3>
<p>Réglages → Données et confidentialité — export en CSV et suppression de
tout, sans courrier et sans attente. Le CSV s'ouvre dans Numbers et Excel.</p>

<h2>Cette application n'est pas un dispositif médical</h2>
<p>Togo ne pose pas de diagnostic et ne prescrit pas de doses. Les décisions
sur la santé de ton chien, c'est toi et ton vétérinaire qui les prenez ;
l'app montre ce que tu y as toi-même mis.</p>
""",
    "footer": """
  <p><a href="privacy.html">Politique de confidentialité</a> ·
     <a href="terms.html">Conditions d'utilisation</a> ·
     <a href="../../fr/index.html">autres applications</a></p>
""",
}
