# Połączenie Google Calendar — konfiguracja lokalna

Komunikat **Missing required parameter: client_id / 400 invalid_request** oznacza, że aplikacja nie ma jeszcze identyfikatora klienta OAuth. Samo konto Google nie wystarcza — trzeba zarejestrować tę aplikację w Google Cloud. Nie podawaj hasła do swojego konta ani sekretu klienta na czacie.

1. Otwórz [Google Cloud Console](https://console.cloud.google.com/) i utwórz lub wybierz projekt.
2. W [bibliotece API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com) włącz **Google Calendar API**.
3. Otwórz [Google Auth Platform](https://console.cloud.google.com/auth/overview). Uzupełnij nazwę aplikacji (np. TRMNL Calendar), adres kontaktowy i wymagane pola.
4. W **Audience / Odbiorcy** wybierz **External / Zewnętrzni**, pozostaw aplikację w trybie **Testing / Testowanie** i dodaj swój adres Google do **Test users / Użytkownicy testowi**. Dodaj też drugie konto, jeśli chcesz połączyć dwa.
5. W **Data Access / Dostęp do danych** dodaj zakres `https://www.googleapis.com/auth/calendar.readonly`.
6. W [Clients / Klienci](https://console.cloud.google.com/auth/clients) utwórz klienta typu **Web application / Aplikacja internetowa**.
7. W **Authorized redirect URIs / Autoryzowane identyfikatory URI przekierowania** dodaj dokładnie:

   ```text
   http://localhost:4010/oauth/callback
   ```

   Wpisz go jako URI przekierowania, a nie JavaScript origin. Port, host i ścieżka muszą się zgadzać. `localhost` i `127.0.0.1` są różnymi hostami.

8. Pobierz JSON klienta. Zapisz go w tym projekcie jako `.tmp/google-oauth.json` (katalog `.tmp` jest wyłączony z Gita) albo przechowuj poza repozytorium. Ogranicz uprawnienia pliku do swojego użytkownika.
9. Zatrzymaj poprzedni proces serwera, następnie uruchom z katalogu projektu:

   ```sh
   python3 scripts/start_dev.py --google-client-json .tmp/google-oauth.json
   ```

   Skrypt wczytuje identyfikator i sekret wyłącznie do środowiska procesu. Nie wypisuje ich. Automatycznie używa portu **4010** i właściwego callbacku. Kolejne uruchomienia mogą używać `python3 scripts/start_dev.py`, jeśli JSON pozostaje w domyślnym miejscu.

10. Otwórz **http://localhost:4010**, zaloguj się hasłem lokalnym `development-password` i kliknij **+ Konto Google**. Przyznaj aplikacji dostęp tylko do odczytu. Wybierz kalendarze i uruchom synchronizację.

Sprawdzenie samej konfiguracji bez uruchamiania serwera:

```sh
python3 scripts/start_dev.py --google-client-json .tmp/google-oauth.json --check
```

Możesz też podać zmienne `GOOGLE_CLIENT_ID` i `GOOGLE_CLIENT_SECRET` przed uruchomieniem skryptu. Nigdy nie zapisuj sekretów w plikach śledzonych przez Git. W Docker Compose używaj zmiennych w `.env`, zgodnie z README; skrypt powyżej dotyczy lokalnego serwera Mix.

## Inne błędy

- **redirect_uri_mismatch**: popraw autoryzowany URI w kliencie Google. Dla innego portu zmień URI oraz `--port`; jawna zmienna `GOOGLE_REDIRECT_URI` ma pierwszeństwo.
- **access_denied / aplikacja niedostępna dla użytkownika**: sprawdź listę użytkowników testowych i ewentualną politykę administratora Google Workspace. Nie zmieniaj ustawień organizacji bez uzgodnienia.
- **OAuth state invalid or expired**: rozpocznij ponownie z `http://localhost:4010` w tej samej przeglądarce. Nie zaczynaj z `127.0.0.1`, gdy callback używa `localhost`.
- **Dostęp przestał działać po kilku dniach**: Google ogranicza ważność tokenów odświeżania dla zewnętrznych aplikacji w trybie Testing; ponownie połącz konto lub skonfiguruj status produkcyjny zgodnie z wymaganiami Google.

Źródło: [dokumentacja Google OAuth dla aplikacji serwerowych](https://developers.google.com/identity/protocols/oauth2/web-server).
