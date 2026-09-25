# Przegląd UX i gotowości do wdrożenia — 25.09.2026

Zakres: logowanie, treści rodzinne, edytor, kalendarze, podgląd/publikacja, konfiguracja Google, parowanie, diagnostyka oraz obsługa telefonu w LAN. Przegląd oparto na kodzie, testach interakcji w Chromium, zrzutach desktop/mobile i obrazach z rzeczywistego renderera. Próba interaktywnego połączenia z przeglądarką użytkownika była niestabilna; weryfikację wykonano w izolowanym środowisku testowym.

## Ustalenia i poprawki

| Priorytet | Problem | Wprowadzona poprawka / wynik |
| --- | --- | --- |
| Wysoki | Godzina z deklaracją ±5 min byłaby nieaktualna przy pobieraniu co 15 min | Czas Europe/Warsaw zapisany w obrazie, generowanie co minutę, pobieranie co 4 min wyłącznie dla opublikowanego układu z zegarem. Bez zegara nadal 15 min. Przy awarii pozostaje starszy obraz; ograniczenie opisano w panelu i instrukcji. |
| Wysoki | Błąd hasła usuwał cały formularz | Pełny ekran logowania pozostaje widoczny, komunikat ma `role=alert`, hasło nie jest odtwarzane. |
| Wysoki | Użytkownik mógł uznać stary podgląd za aktualny po edycji geometrii lub stylu | Komunikat o zmianie układu od czasu podglądu oraz instrukcja odświeżania po zmianie treści. Publikacja nadal izoluje szkic. |
| Średni | Zbyt dużo pustej przestrzeni i przewijania | Mniejszy nagłówek, marginesy, odstępy i panele; zwarte bloki obrazu. Wybór zwartych/swobodnych odstępów osobno dla bloku. |
| Średni | Brak wyboru wyglądu kalendarza | Agenda zwykła lub grupowana dniami, tydzień w kolumnach lub wierszach, miesiąc z liczbą wydarzeń. Style klasyczny, minimalny i kontrastowy. |
| Średni | Miesiąc mógł sugerować brak wydarzeń tam, gdzie synchronizacja nie obejmuje starych dat | Znak „—” i legenda dla dat starszych niż okno synchronizacji; miesiąc służy do orientacji, szczegóły są w agendzie. |
| Średni | Techniczne nazwy i daty UTC | Polskie nazwy bloków i geometrii, lokalny format czasu w statusie, synchronizacji i diagnostyce. |
| Średni | Przejście z bloku do treści wymagało ponownego znalezienia modułu | „Edytuj treść” otwiera właściwy moduł rodzinny i zachowuje roboczy układ. |
| Średni | Istniejące bloki trudno było wybrać klawiaturą | Focus i Enter/Spacja otwierają ustawienia bloku; zakładki obsługują strzałki i Home/End. Geometria ma pola liczbowe. |
| Średni | Elementy interfejsu na telefonie były zbyt małe | Formularze mają tekst 16 px, przyciski min. 44 px i pojedynczą kolumnę. Przewijanie siatki jest lokalne; sam obraz zachowuje 800×480. |
| Niski | Nie było prostej drogi od źródeł do wdrożenia | Instrukcja LAN, kontrola `.env` bez wypisywania sekretów, kopia bazy, ograniczenie logów oraz paczka źródłowa z sumą SHA-256. |

## Przepływy sprawdzone testami

- Logowanie poprawne/błędne, dostęp bez sesji, ponowna próba logowania.
- Dodawanie, edycja, usuwanie, limit dzienny, wykonanie i cofanie zadań; pozostałe cztery moduły rodzinne.
- Dodawanie, przesuwanie, skalowanie, wybór klawiaturą, odrzucenie kolizji, zapis i ponowne otwarcie układu.
- Style kalendarzy, gęstość, podgląd, publikacja, izolacja niezapisanych i nieopublikowanych zmian.
- Google: dwa konta przez deterministyczne fixture’y, paginacja, wyjątki cykliczne, anulowania, strefy czasowe, błędy synchronizacji i brak konfiguracji OAuth.
- Parowanie symulowanego urządzenia, autoryzacja, pobranie obrazu, logi i telemetria.
- Awaria renderera, zachowanie obrazu, ponowienie i trwałość po restarcie Compose.

## Ograniczenia pozostające przed użyciem domowym

- Nie wykonano testu użyteczności z domownikami ani testu fizycznego TRMNL. Czytelność potwierdzono na PNG, nie na panelu e-ink.
- Integracja prawdziwych kont Google wymaga zgody użytkownika. Zadania są lokalne; nie dodano Google Tasks ani innych providerów.
- Mobilny dashboard wymaga dostępu do LAN; nie ma kolejki offline ani osobnej aplikacji PWA. To pozostaje poza uzgodnionym wdrożeniem.
- Bardzo małe bloki nadal mogą pokazywać „Więcej ↓”; przed publikacją należy sprawdzić podgląd.
- Nie podano docelowego adresu serwera. Paczka jest przygotowana do uruchomienia, ale nie oznacza to zdalnego wdrożenia.

Instrukcja operacyjna: [DEPLOY_LAN.md](DEPLOY_LAN.md). Wyniki uruchomień: [VALIDATION.md](VALIDATION.md).
