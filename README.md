# Neovim.app per macOS

Un launcher macOS che apre Neovim in una finestra WezTerm dedicata. `Neovim.app`
è l'unica app visibile nel Dock, con nome e icona Neovim: facendo clic sulla sua
icona si torna alla sessione esistente. Il terminale incorporato gestisce la
finestra come app accessoria e non aggiunge un'altra icona al Dock né una propria
barra dei menu. Il launcher termina quando si chiude l'ultima sessione.
WezTerm avviato normalmente rimane un'app indipendente.

Aprire un file tramite `Neovim.app` mentre una sessione è già attiva riutilizza
quella sessione, senza creare un'altra finestra. Se Yazi sta ancora scegliendo
il workspace, il file resta in attesa finché Neovim non si avvia.

Solo nella sessione Neovim, le scorciatoie per creare tab, finestre o split,
collegarsi ad altri domini o aprire il launcher dei comandi sono disattivate;
chiudere la sessione resta possibile. Il fork blocca anche eventuali comandi
equivalenti eseguiti da voci di menu residue.

All'avvio senza file, il launcher apre Yazi per scegliere una cartella. `Invio`
conferma, mentre `q`, `Q` ed `Esc` annullano. Il picker eredita la configurazione
Yazi dell'utente, inclusi tema e plugin. La modifica del workspace dentro una
sessione Neovim esistente tramite `:Workspace` o `<leader>fw` richiede
l'[integrazione Neovim](integrations/neovim/workspace.lua).

## Requisiti

- macOS e Xcode Command Line Tools (`xcrun`, `swiftc`, `codesign`).
- Neovim e Yazi installati in `/opt/homebrew/bin` o `/usr/local/bin`.
- Una build `wezterm-gui` del branch
  [`neovim-app`](https://github.com/kevinmuka/wezterm/tree/neovim-app)
  del fork WezTerm. Il launcher è un'app regular, mentre il terminale incluso
  è un'app accessory. Il launcher imposta anche
  `WEZTERM_MACOS_ACTIVATION_POLICY=accessory` quando avvia WezTerm, perché il
  terminale applica una propria policy di attivazione a runtime.
- Per la compilazione dell'app, le risorse di una `WezTerm.app` installata in
  `/Applications`, oppure un'altra directory di risorse indicata esplicitamente.

## Compilazione

Clona e compila il fork WezTerm seguendo le sue istruzioni per macOS. Per
esempio, dopo aver predisposto Rust e le dipendenze richieste dal fork:

```sh
git clone --branch neovim-app --recurse-submodules \
  https://github.com/kevinmuka/wezterm.git wezterm-fork
cd wezterm-fork
cargo build --release -p wezterm-gui
```

Se parti invece dal branch `tab-config-overrides`, applica prima della build
[`wezterm-single-session-menu.patch`](patches/wezterm-single-session-menu.patch).
Il branch `neovim-app` contiene già queste modifiche e non richiede la patch.

Poi, dalla radice di questa repository:

```sh
NEOVIM_WEZTERM_GUI="/percorso/a/wezterm-fork/target/release/wezterm-gui" \
  ./app/build.sh
```

Se `WezTerm.app` non è in `/Applications`, imposta anche
`NEOVIM_WEZTERM_RESOURCES` sulla sua directory `Contents/Resources`.
Lo script rifiuta un binario WezTerm che non contiene il filtro del menu.

Lo script genera `outputs/Neovim.app` e `outputs/Neovim.zip`, li firma localmente
con una firma ad hoc e non li include in Git. L'app non è notarizzata da Apple.
Per installarla, copia `outputs/Neovim.app` in `/Applications`.

## Configurazione personale

La configurazione di Neovim non viene incorporata nell'app: viene caricata
dall'installazione dell'utente. Per abilitare `:Workspace` e `<leader>fw`, copia
[`integrations/neovim/workspace.lua`](integrations/neovim/workspace.lua) nel
tuo percorso Lua di Neovim e chiamane `setup()`. Il modulo usa le risorse in
`/Applications/Neovim.app`; quindi l'app deve trovarsi lì per questa funzione.
Non sovrascrivere una configurazione già personalizzata senza confrontarla.

Per impedire tab, nuove finestre e split **solo nella sessione avviata da
Neovim.app**, copia
[`integrations/wezterm/neovim_app.lua`](integrations/wezterm/neovim_app.lua)
in una directory visibile alla configurazione Lua di WezTerm e chiama
`require("lua.neovim_app").apply(config, wezterm)` prima di `return config`.
L'integrazione riconosce `NEOVIM_APP_SINGLE_SESSION=1` e non cambia le normali
sessioni WezTerm.

Questa repository non include i dotfiles personali completi: i file sotto
`integrations/` sono i soli moduli necessari per le funzioni descritte.

## Contenuto e pubblicazione

`app/` contiene il launcher Swift, i plist, l'icona e gli script del picker.
`integrations/` contiene i moduli da integrare nelle configurazioni personali.
Il binario WezTerm, le build, i backup e i dati temporanei sono esclusi da Git.
Se distribuisci una build dell'app, includi anche gli avvisi di licenza delle
dipendenze: lo script inserisce la licenza MIT di WezTerm nell'helper.

Questa repository non dichiara ancora una licenza per il codice del launcher;
sceglila prima di consentire a terzi di riutilizzarlo.

Per pubblicare i commit, dopo aver configurato `origin`, dalla radice di questa
cartella esegui:

```sh
git push -u origin main
```
