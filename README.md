# Vessel 🚢

Vessel to lekki, natywny interfejs graficzny do zarządzania kontenerami na systemie macOS. Projekt stawia na wysoką wydajność, prostotę użytkowania oraz doskonałą integrację ze środowiskiem Apple.

## O projekcie

Aplikacja została w całości napisana w **SwiftUI**, co gwarantuje nowoczesny i płynny interfejs zgodny z wytycznymi Human Interface Guidelines. Pod maską Vessel komunikuje się bezpośrednio z natywnym API za pośrednictwem frameworka `apple/containerization`, oferując szybkie i niezawodne zarządzanie procesami oraz pełnym cyklem życia kontenerów.

## Główne cechy

- **Natywne Doświadczenie (Native Experience):** Przejrzysty dwupanelowy układ z wykorzystaniem `NavigationSplitView`, idealnie dopasowany do stylistyki macOS.
- **Bezpośrednia Integracja:** Wykorzystanie najnowszego frameworka `apple/containerization` do monitorowania statusu i sterowania kontenerami.
- **Szybki Podgląd:** Czytelne oznaczenie stanu każdego kontenera (Running, Stopped, Paused) pozwala na błyskawiczną ocenę sytuacji.
- **Pełna Kontrola:** Przejrzyste, natywne przyciski pozwalające na asynchroniczne uruchamianie i zatrzymywanie kontenerów bezpośrednio z poziomu panelu szczegółów.

## Wymagania systemowe

- **System Operacyjny:** macOS 13.0 lub nowszy
- **Język:** Swift 5.9+

## Technologie

- **SwiftUI** (najnowsze standardy, w tym makro `@Observable`)
- **Swift Package Manager (SPM)** - projekt nie posiada ciężkich plików konfiguracyjnych Xcode `.xcodeproj`.
- Obiektowe zarządzanie procesami asynchronicznymi z użyciem `async/await`.

## Budowanie i uruchamianie

Ze względu na to, że projekt opiera się o SPM (Swift Package Manager), kompilacja i odpalenie aplikacji jest niezwykle proste.
Będąc w głównym katalogu projektu, po prostu wywołaj w terminalu polecenie:

```bash
swift run
```

Ewentualnie, jeśli wolisz pracować z Xcode, wystarczy otworzyć plik `Package.swift` w tym środowisku, a struktura projektu zostanie załadowana automatycznie.

## Struktura plików

- `Package.swift` - Deklaracja zależności (w tym pakietu `apple/containerization`) oraz konfiguracja aplikacji wykonywalnej.
- `Sources/Vessel/App.swift` - Główny punkt startowy aplikacji `@main`.
- `Sources/Vessel/ContentView.swift` - Prawa i lewa kolumna widoku (lista oraz detale) napisane w SwiftUI.
- `Sources/Vessel/ContainerViewModel.swift` - Model widoku zarządzający logiką i wywołaniami UI.
- `Sources/Vessel/ContainerDaemon.swift` - Warstwa łącząca Vessel z natywnym API środowiska Apple.

---
*Vessel - Twoje centrum dowodzenia kontenerami na Macu.*
