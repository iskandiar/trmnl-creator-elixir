# Wdrożenie w sieci lokalnej

Pakiet jest przygotowany dla jednego TRMNL OG i serwera **amd64** z Docker Engine / Compose v2. Nie wymaga publicznej domeny ani otwierania portów na routerze. Telefon i TRMNL muszą mieć dostęp do adresu LAN serwera. Internet wychodzący jest potrzebny do pierwszego pobrania zależności i Google Calendar; lokalne zadania, posiłki i notatki nie wymagają konta Google.

## Instalacja

Paczka `dist/trmnl-calendar.tar.gz` zawiera aplikację, gotowe zasoby przeglądarki, Compose i skrypty operacyjne. Nie zawiera `.env`, pobranych danych OAuth, bazy, obrazów użytkownika ani katalogu `.tmp`. Jest to paczka źródłowa: obrazy amd64 budowane są na serwerze.

```sh
# W katalogu z otrzymaną paczką i plikiem .sha256:
sha256sum -c trmnl-calendar.tar.gz.sha256
tar -xzf trmnl-calendar.tar.gz
cd trmnl-calendar
python3 scripts/generate_env.py
```

Uzupełnij `.env`:

- `PUBLIC_URL=http://ADRES_LAN_SERWERA:4000` — rzeczywisty adres dostępny z telefonu i TRMNL, nie `localhost`. Ustaw stałą rezerwację adresu serwera w DHCP.
- `PORT=4000` — port udostępniony przez Docker. Musi odpowiadać portowi w `PUBLIC_URL`.
- `BIND_ADDRESS=0.0.0.0` lub konkretny adres interfejsu LAN serwera.
- `COMPOSE_PROJECT_NAME=trmnl` — zachowaj tę nazwę podczas aktualizacji i wykonywania kopii.
- Pozostałe sekrety generuje skrypt. Hasło panelu znajdziesz w `ADMIN_PASSWORD`.

```sh
python3 scripts/preflight.py .env
docker compose config --quiet
docker compose up --build -d --wait
docker compose ps
curl -fsS http://ADRES_LAN_SERWERA:4000/health
```

W LAN zaufanym przez domowników można używać HTTP. Jeśli sieć jest współdzielona z osobami niezaufanymi, skonfiguruj HTTPS na lokalnym reverse proxy; przekazuj WebSocket `/live/websocket` i zachowaj ten sam adres w `PUBLIC_URL`. Nie przekierowuj portu aplikacji z internetu.

## Pierwsze uruchomienie

1. Otwórz `PUBLIC_URL`, zaloguj się wygenerowanym hasłem.
2. Dodaj dane w **Treść rodzinna**. **3 zadania na dziś** ma limit trzech wpisów na datę, także wykonanych.
3. W **Układ ekranu** dodaj bloki, ustaw wygląd i sprawdź Podgląd. Zapis szkicu nie zmienia urządzenia; **Publikuj na TRMNL** aktywuje obraz.
4. Połącz Google Calendar zgodnie z [instrukcją Google](GOOGLE_SETUP.md). Dla domowego serwera użyj callbacku localhost przez tunel SSH; muszą się zgadzać `GOOGLE_BROWSER_ORIGIN`, `GOOGLE_REDIRECT_URI` i adres dozwolony w Google Cloud. Dane OAuth dodaj do `.env`, nigdy do plików źródłowych.
5. W **Kalendarze i urządzenie** otwórz parowanie dla MAC urządzenia. W konfiguracji BYOS urządzenia podaj `PUBLIC_URL`. Okno parowania trwa 10 minut.

Ekran z blokiem daty/godziny jest generowany co minutę i pobierany przez TRMNL co 4 minuty. „±5 min” opisuje przybliżenie przy sprawnym serwerze, sieci i urządzeniu; to czas obrazu, nie sekundowy zegar. Przy awarii pozostaje poprzedni obraz. Bez zegara interwał urządzenia wynosi 15 minut. Częstsze pobieranie może skrócić czas pracy na baterii. Serwer powinien mieć poprawny czas systemowy; wyświetlanie używa Europe/Warsaw.

## Kopia i odtwarzanie

```sh
sh scripts/backup.sh .env /SCIEZKA/DO/KOPII/trmnl.dump
```

Skrypt nie nadpisuje istniejącego pliku i tworzy kopię z ograniczonymi uprawnieniami. Kopia zawiera prywatne treści rodziny, więc przechowuj ją bezpiecznie. Zachowaj także `.env`, szczególnie `TOKEN_ENCRYPTION_KEY`; bez niego nie odczytasz zapisanych tokenów Google.

Odtwarzanie **zastępuje zawartość docelowej bazy**. Przeprowadź je na właściwym projekcie Compose, po wykonaniu kopii obecnego stanu:

```sh
docker compose stop app
docker compose exec -T db pg_restore -U trmnl -d trmnl --clean --if-exists < /SCIEZKA/DO/KOPII/trmnl.dump
docker compose up -d --wait app
```

## Aktualizacja i diagnostyka

Przed aktualizacją wykonaj kopię, zachowaj `.env` i nazwę projektu. Wgraj nowe źródła, następnie uruchom `docker compose up --build -d --wait`. Migracje wykonują się przy starcie aplikacji. Nie generuj ponownie klucza szyfrowania.

```sh
docker compose ps
docker compose logs --tail=100 app renderer
```

Przy problemach sprawdź: zdrowie usług, adres LAN i izolację klientów Wi-Fi, wybór kalendarzy, ważność zgody Google, ostatni kontakt urządzenia i diagnostykę panelu. Po naprawie renderera możesz ponowić podgląd/publikację lub synchronizację. Rotacja logów ogranicza ich wielkość. `docker compose down` zachowuje bazę; `down -v` ją usuwa.

## Co pozostaje do potwierdzenia na docelowym serwerze

- Rzeczywisty adres/IP LAN, port, routing telefonu i TRMNL.
- Zgoda prawdziwych kont Google i odczyt ich kalendarzy.
- Fizyczne parowanie OG, obsługa PNG przez firmware, odświeżanie oraz czytelność na urządzeniu.
- Lokalna polityka kopii, pojemność dysku i powrót usług po restarcie serwera.

Testy na komputerze deweloperskim i symulowanym urządzeniu nie potwierdzają tych punktów. Nie wdrożono aplikacji na niepodanym serwerze docelowym.
