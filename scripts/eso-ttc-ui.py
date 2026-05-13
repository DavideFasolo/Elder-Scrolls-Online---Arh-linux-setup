#!/usr/bin/env python3

import os
import re
import signal
import subprocess
import threading
from pathlib import Path
from tkinter import messagebox

try:
    import customtkinter as ctk
except ModuleNotFoundError:
    print(
        "ERRORE: customtkinter non è installato.\n"
        "Esegui prima scripts/setup-ttc-updater.sh, che crea la venv dedicata,\n"
        "oppure installalo manualmente nella venv usata dal launcher."
    )
    raise SystemExit(1)


WRAPPER = Path(os.environ.get("ESO_TTC_WRAPPER", Path.home() / "scripts/games/eso-ttc.sh"))

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
OSC_RE = re.compile(r"\x1b\].*?(?:\x07|\x1b\\)")
CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
COUNTDOWN_RE = re.compile(r"Countdown:\s*(\d{2}:\d{2})", re.IGNORECASE)


class EsoTtcUI(ctk.CTk):
    def __init__(self):
        super().__init__()

        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")

        self.title("ESO Tamriel Trade Centre")
        self.geometry("860x600")
        self.minsize(740, 520)

        self.proc = None
        self.ui_loop_active = False
        self.countdown_job = None
        self.countdown_remaining = 0
        self.current_server = "eu"

        self.server_var = ctk.StringVar(value="EU")
        self.mode_var = ctk.StringVar(value="Once")

        self.grid_columnconfigure(0, weight=0)
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(1, weight=1)

        self._build_header()
        self._build_controls()
        self._build_output()
        self._build_status_bar()

        self.protocol("WM_DELETE_WINDOW", self.on_close)

    def _build_header(self):
        header = ctk.CTkFrame(self, corner_radius=0)
        header.grid(row=0, column=0, columnspan=2, sticky="ew")
        header.grid_columnconfigure(0, weight=1)

        title = ctk.CTkLabel(
            header,
            text="ESO Tamriel Trade Centre",
            font=ctk.CTkFont(size=24, weight="bold"),
            anchor="w",
        )
        title.grid(row=0, column=0, sticky="ew", padx=18, pady=(14, 2))

        subtitle = ctk.CTkLabel(
            header,
            text=f"Wrapper: {WRAPPER}",
            font=ctk.CTkFont(size=12),
            text_color=("gray35", "gray70"),
            anchor="w",
        )
        subtitle.grid(row=1, column=0, sticky="ew", padx=18, pady=(0, 14))

    def _build_controls(self):
        sidebar = ctk.CTkFrame(self, corner_radius=18)
        sidebar.grid(row=1, column=0, sticky="nsw", padx=(14, 8), pady=14)
        sidebar.grid_columnconfigure(0, weight=1)

        server_title = ctk.CTkLabel(
            sidebar,
            text="Server",
            font=ctk.CTkFont(size=15, weight="bold"),
            anchor="w",
        )
        server_title.grid(row=0, column=0, sticky="ew", padx=16, pady=(16, 6))

        self.server_selector = ctk.CTkSegmentedButton(
            sidebar,
            values=["EU", "NA"],
            variable=self.server_var,
        )
        self.server_selector.grid(row=1, column=0, sticky="ew", padx=16, pady=(0, 18))

        mode_title = ctk.CTkLabel(
            sidebar,
            text="Modalità",
            font=ctk.CTkFont(size=15, weight="bold"),
            anchor="w",
        )
        mode_title.grid(row=2, column=0, sticky="ew", padx=16, pady=(0, 6))

        self.mode_selector = ctk.CTkSegmentedButton(
            sidebar,
            values=["Once", "Loop"],
            variable=self.mode_var,
        )
        self.mode_selector.grid(row=3, column=0, sticky="ew", padx=16, pady=(0, 8))

        mode_hint = ctk.CTkLabel(
            sidebar,
            text="Once aggiorna e chiude.\nLoop è gestito dalla UI: esegue once ogni 60 minuti.",
            justify="left",
            text_color=("gray35", "gray70"),
            font=ctk.CTkFont(size=12),
        )
        mode_hint.grid(row=4, column=0, sticky="ew", padx=16, pady=(0, 18))

        actions_title = ctk.CTkLabel(
            sidebar,
            text="Azioni",
            font=ctk.CTkFont(size=15, weight="bold"),
            anchor="w",
        )
        actions_title.grid(row=5, column=0, sticky="ew", padx=16, pady=(0, 8))

        self.run_btn = ctk.CTkButton(
            sidebar,
            text="Avvia updater",
            command=self.run_updater,
            height=38,
        )
        self.run_btn.grid(row=6, column=0, sticky="ew", padx=16, pady=(0, 8))

        self.stop_btn = ctk.CTkButton(
            sidebar,
            text="Ferma",
            command=self.stop_updater,
            height=36,
            state="disabled",
            fg_color="#7a2e2e",
            hover_color="#943838",
        )
        self.stop_btn.grid(row=7, column=0, sticky="ew", padx=16, pady=(0, 8))

        self.status_btn = ctk.CTkButton(
            sidebar,
            text="Status",
            command=self.run_status,
            height=36,
            fg_color="#3b5f8a",
            hover_color="#4b74a5",
        )
        self.status_btn.grid(row=8, column=0, sticky="ew", padx=16, pady=(0, 8))

        self.clear_btn = ctk.CTkButton(
            sidebar,
            text="Pulisci output",
            command=self.clear_output,
            height=36,
            fg_color="#444444",
            hover_color="#555555",
        )
        self.clear_btn.grid(row=9, column=0, sticky="ew", padx=16, pady=(0, 18))

        path_card = ctk.CTkFrame(sidebar, corner_radius=14, fg_color=("gray88", "gray18"))
        path_card.grid(row=10, column=0, sticky="ew", padx=16, pady=(4, 16))
        path_card.grid_columnconfigure(0, weight=1)

        path_label = ctk.CTkLabel(
            path_card,
            text="Usa il wrapper eso-ttc.sh.\nNon usa --steam.",
            justify="left",
            text_color=("gray30", "gray75"),
            font=ctk.CTkFont(size=12),
        )
        path_label.grid(row=0, column=0, sticky="ew", padx=12, pady=12)

    def _build_output(self):
        panel = ctk.CTkFrame(self, corner_radius=18)
        panel.grid(row=1, column=1, sticky="nsew", padx=(8, 14), pady=14)
        panel.grid_rowconfigure(1, weight=1)
        panel.grid_columnconfigure(0, weight=1)

        output_title = ctk.CTkLabel(
            panel,
            text="Output",
            font=ctk.CTkFont(size=15, weight="bold"),
            anchor="w",
        )
        output_title.grid(row=0, column=0, sticky="ew", padx=16, pady=(14, 8))

        self.output = ctk.CTkTextbox(
            panel,
            wrap="word",
            font=("monospace", 12),
            corner_radius=12,
        )
        self.output.grid(row=1, column=0, sticky="nsew", padx=16, pady=(0, 16))

    def _build_status_bar(self):
        status = ctk.CTkFrame(self, height=38, corner_radius=0)
        status.grid(row=2, column=0, columnspan=2, sticky="ew")
        status.grid_columnconfigure(1, weight=1)

        self.status_badge = ctk.CTkLabel(
            status,
            text="Pronto",
            font=ctk.CTkFont(size=12, weight="bold"),
            fg_color="#2f6f4e",
            corner_radius=12,
            width=110,
        )
        self.status_badge.grid(row=0, column=0, padx=(14, 8), pady=8)

        self.status_text = ctk.CTkLabel(
            status,
            text="Scegli server e modalità, poi avvia.",
            anchor="w",
            text_color=("gray35", "gray70"),
        )
        self.status_text.grid(row=0, column=1, sticky="ew", padx=(0, 14), pady=8)

    def append(self, text):
        self.output.insert("end", text)
        self.output.see("end")

    def clear_output(self):
        self.output.delete("1.0", "end")

    def set_state_idle(self, text="Pronto", detail=""):
        self.run_btn.configure(state="normal")
        self.status_btn.configure(state="normal")
        self.server_selector.configure(state="normal")
        self.mode_selector.configure(state="normal")
        self.stop_btn.configure(state="disabled")
        self.status_badge.configure(text=text, fg_color="#2f6f4e")
        self.status_text.configure(text=detail or "Scegli server e modalità, poi avvia.")

    def set_state_running(self, detail="Updater in esecuzione"):
        self.run_btn.configure(state="disabled")
        self.status_btn.configure(state="disabled")
        self.server_selector.configure(state="disabled")
        self.mode_selector.configure(state="disabled")
        self.stop_btn.configure(state="normal")
        self.status_badge.configure(text="In esecuzione", fg_color="#3b5f8a")
        self.status_text.configure(text=detail)

    def set_state_error(self, detail):
        self.run_btn.configure(state="normal")
        self.status_btn.configure(state="normal")
        self.server_selector.configure(state="normal")
        self.mode_selector.configure(state="normal")
        self.stop_btn.configure(state="disabled")
        self.status_badge.configure(text="Errore", fg_color="#7a2e2e")
        self.status_text.configure(text=detail)

    def check_wrapper(self):
        if not WRAPPER.exists():
            messagebox.showerror("Wrapper mancante", f"Non trovo il wrapper:\n{WRAPPER}")
            return False

        if not os.access(WRAPPER, os.X_OK):
            messagebox.showerror("Wrapper non eseguibile", f"Il wrapper esiste ma non è eseguibile:\n{WRAPPER}")
            return False

        return True

    def set_state_waiting(self, detail):
        self.run_btn.configure(state="disabled")
        self.status_btn.configure(state="disabled")
        self.server_selector.configure(state="disabled")
        self.mode_selector.configure(state="disabled")
        self.stop_btn.configure(state="normal")
        self.status_badge.configure(text="In attesa", fg_color="#6b5f2a")
        self.status_text.configure(text=detail)

    def cancel_countdown(self):
        if self.countdown_job is not None:
            try:
                self.after_cancel(self.countdown_job)
            except Exception:
                pass
            self.countdown_job = None
        self.countdown_remaining = 0

    def format_countdown(self, seconds):
        minutes, secs = divmod(max(0, seconds), 60)
        hours, minutes = divmod(minutes, 60)

        if hours:
            return f"{hours:02d}:{minutes:02d}:{secs:02d}"

        return f"{minutes:02d}:{secs:02d}"

    def start_ui_countdown(self, seconds=3600):
        self.cancel_countdown()
        self.countdown_remaining = seconds
        self.tick_ui_countdown()

    def tick_ui_countdown(self):
        if not self.ui_loop_active:
            self.cancel_countdown()
            return

        if self.countdown_remaining <= 0:
            self.countdown_job = None
            self.start_loop_iteration()
            return

        label = self.format_countdown(self.countdown_remaining)
        self.set_state_waiting(f"Prossimo controllo tra {label}")

        self.countdown_remaining -= 1
        self.countdown_job = self.after(1000, self.tick_ui_countdown)

    def start_loop_iteration(self):
        if not self.ui_loop_active:
            return

        if self.proc is not None:
            return

        self.cancel_countdown()

        cmd = [str(WRAPPER), f"--{self.current_server}", "--once"]

        self.append("Comando ciclo loop:\n")
        self.append(" ".join(cmd) + "\n\n")

        self.start_process(cmd, f"Server {self.current_server.upper()}, loop UI: ciclo once")

    def run_status(self):
        if self.proc is not None:
            return

        if not self.check_wrapper():
            return

        self.clear_output()
        self.start_process([str(WRAPPER), "--status"], "Lettura status...")

    def run_updater(self):
        if self.proc is not None or self.ui_loop_active:
            return

        if not self.check_wrapper():
            return

        server = self.server_var.get().lower()
        mode = self.mode_var.get().lower()

        self.current_server = server
        self.ui_loop_active = mode == "loop"

        self.clear_output()

        if self.ui_loop_active:
            self.append("Loop gestito dalla UI: eseguo un ciclo --once ogni 60 minuti.\n\n")
            self.start_loop_iteration()
            return

        cmd = [str(WRAPPER), f"--{server}", "--once"]

        self.append("Comando:\n")
        self.append(" ".join(cmd) + "\n\n")

        self.start_process(cmd, f"Server {server.upper()}, modalità once")

    def start_process(self, cmd, detail):
        try:
            self.proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                preexec_fn=os.setsid,
            )
        except Exception as exc:
            self.proc = None
            self.set_state_error(str(exc))
            messagebox.showerror("Errore avvio", str(exc))
            return

        self.set_state_running(detail)

        thread = threading.Thread(target=self.read_process_output, daemon=True)
        thread.start()

    def read_process_output(self):
        try:
            assert self.proc is not None
            assert self.proc.stdout is not None

            buffer = []

            while True:
                char = self.proc.stdout.read(1)

                if char == "":
                    break

                if char == "\r":
                    self.flush_output_buffer(buffer, transient=True)
                    buffer = []
                    continue

                if char == "\n":
                    self.flush_output_buffer(buffer, transient=False)
                    buffer = []
                    continue

                buffer.append(char)

            self.flush_output_buffer(buffer, transient=False)

            return_code = self.proc.wait()
            self.after(0, self.process_finished, return_code)
        except Exception as exc:
            self.after(0, self.process_failed, str(exc))

    def clean_terminal_text(self, text):
        text = OSC_RE.sub("", text)
        text = ANSI_RE.sub("", text)
        text = text.replace("\x07", "")
        text = CONTROL_RE.sub("", text)
        return text

    def flush_output_buffer(self, buffer, transient=False):
        if not buffer:
            return

        raw_text = "".join(buffer)
        clean = self.clean_terminal_text(raw_text).strip()
        match = COUNTDOWN_RE.search(clean)

        if match:
            countdown = match.group(1)
            self.after(0, self.update_countdown_status, countdown)
            return

        if transient:
            # Righe riscritte con carriage return non countdown:
            # le mostriamo come evento normale solo se contengono testo utile.
            if clean:
                self.after(0, self.append, clean + "\n")
            return

        display_text = self.clean_terminal_text(raw_text).rstrip()

        if display_text:
            self.after(0, self.append, display_text + "\n")

    def update_countdown_status(self, countdown):
        self.status_badge.configure(text="In attesa", fg_color="#6b5f2a")
        self.status_text.configure(text=f"Prossimo controllo tra {countdown}")

    def process_finished(self, return_code):
        self.append(f"\nProcesso terminato con codice: {return_code}\n")

        self.proc = None

        if return_code == 0:
            if self.ui_loop_active:
                self.append("\nCiclo completato. Avvio timer UI da 60 minuti.\n")
                self.start_ui_countdown(3600)
            else:
                self.set_state_idle("Completato", "Processo terminato correttamente.")
        elif return_code in (-signal.SIGTERM, 128 + signal.SIGTERM, 143):
            self.ui_loop_active = False
            self.cancel_countdown()
            self.set_state_idle("Fermato", "Updater interrotto dall'utente. Timer azzerato.")
        else:
            self.ui_loop_active = False
            self.cancel_countdown()
            self.set_state_error(f"Processo terminato con codice {return_code}.")

    def process_failed(self, error):
        self.append(f"\nErrore processo: {error}\n")
        self.proc = None
        self.set_state_error(error)

    def stop_updater(self):
        if self.proc is None and not self.ui_loop_active:
            return

        self.ui_loop_active = False
        self.cancel_countdown()

        if self.proc is None:
            self.append("\nLoop fermato. Timer azzerato.\n")
            self.set_state_idle("Fermato", "Loop interrotto dall'utente. Timer azzerato.")
            return

        try:
            os.killpg(os.getpgid(self.proc.pid), signal.SIGTERM)
            self.append("\nRichiesto stop updater...\n")
            self.status_badge.configure(text="Stop richiesto", fg_color="#7a5a2e")
            self.status_text.configure(text="Timer azzerato, interruzione in corso.")
        except Exception as exc:
            self.set_state_error(str(exc))
            messagebox.showerror("Errore stop", str(exc))

    def on_close(self):
        if self.proc is not None or self.ui_loop_active:
            answer = messagebox.askyesno(
                "Updater attivo",
                "L'updater è ancora in esecuzione o in attesa loop. Vuoi fermarlo e chiudere?",
            )
            if not answer:
                return
            self.stop_updater()

        self.destroy()


if __name__ == "__main__":
    app = EsoTtcUI()
    app.mainloop()
