#!/usr/bin/env python3

import os
import signal
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox
from tkinter.scrolledtext import ScrolledText


WRAPPER = Path(os.environ.get("ESO_TTC_WRAPPER", Path.home() / "scripts/games/eso-ttc.sh"))


class EsoTtcUI(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("ESO TTC Updater")
        self.geometry("760x520")
        self.minsize(620, 420)

        self.proc = None
        self.server_var = tk.StringVar(value="eu")
        self.mode_var = tk.StringVar(value="once")

        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self.on_close)

    def _build_ui(self):
        root = tk.Frame(self, padx=12, pady=12)
        root.pack(fill=tk.BOTH, expand=True)

        title = tk.Label(
            root,
            text="Tamriel Trade Centre Updater",
            font=("Sans", 16, "bold"),
            anchor="w",
        )
        title.pack(fill=tk.X)

        subtitle = tk.Label(root, text=f"Wrapper: {WRAPPER}", anchor="w")
        subtitle.pack(fill=tk.X, pady=(2, 12))

        options = tk.Frame(root)
        options.pack(fill=tk.X, pady=(0, 10))

        server_box = tk.LabelFrame(options, text="Server", padx=10, pady=8)
        server_box.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))

        tk.Radiobutton(server_box, text="EU", variable=self.server_var, value="eu").pack(anchor="w")
        tk.Radiobutton(server_box, text="NA", variable=self.server_var, value="na").pack(anchor="w")

        mode_box = tk.LabelFrame(options, text="Modalità", padx=10, pady=8)
        mode_box.pack(side=tk.LEFT, fill=tk.X, expand=True)

        tk.Radiobutton(
            mode_box,
            text="Once: aggiorna una volta e chiude",
            variable=self.mode_var,
            value="once",
        ).pack(anchor="w")

        tk.Radiobutton(
            mode_box,
            text="Loop: resta aperto e aggiorna periodicamente",
            variable=self.mode_var,
            value="loop",
        ).pack(anchor="w")

        buttons = tk.Frame(root)
        buttons.pack(fill=tk.X, pady=(0, 10))

        self.run_btn = tk.Button(buttons, text="Avvia updater", command=self.run_updater, width=18)
        self.run_btn.pack(side=tk.LEFT)

        self.stop_btn = tk.Button(
            buttons,
            text="Ferma",
            command=self.stop_updater,
            width=12,
            state=tk.DISABLED,
        )
        self.stop_btn.pack(side=tk.LEFT, padx=(8, 0))

        self.status_btn = tk.Button(buttons, text="Status", command=self.run_status, width=12)
        self.status_btn.pack(side=tk.LEFT, padx=(8, 0))

        self.clear_btn = tk.Button(buttons, text="Pulisci output", command=self.clear_output, width=14)
        self.clear_btn.pack(side=tk.RIGHT)

        self.output = ScrolledText(root, wrap=tk.WORD, height=18)
        self.output.pack(fill=tk.BOTH, expand=True)

        self.status_label = tk.Label(root, text="Pronto", anchor="w")
        self.status_label.pack(fill=tk.X, pady=(8, 0))

    def append(self, text):
        self.output.insert(tk.END, text)
        self.output.see(tk.END)

    def clear_output(self):
        self.output.delete("1.0", tk.END)

    def set_running(self, running):
        if running:
            self.run_btn.config(state=tk.DISABLED)
            self.status_btn.config(state=tk.DISABLED)
            self.stop_btn.config(state=tk.NORMAL)
            self.status_label.config(text="Updater in esecuzione")
        else:
            self.run_btn.config(state=tk.NORMAL)
            self.status_btn.config(state=tk.NORMAL)
            self.stop_btn.config(state=tk.DISABLED)
            self.status_label.config(text="Pronto")

    def check_wrapper(self):
        if not WRAPPER.exists():
            messagebox.showerror("Wrapper mancante", f"Non trovo il wrapper:\n{WRAPPER}")
            return False

        if not os.access(WRAPPER, os.X_OK):
            messagebox.showerror("Wrapper non eseguibile", f"Il wrapper esiste ma non è eseguibile:\n{WRAPPER}")
            return False

        return True

    def run_status(self):
        if self.proc is not None:
            return

        if not self.check_wrapper():
            return

        self.clear_output()
        self.start_process([str(WRAPPER), "--status"])

    def run_updater(self):
        if self.proc is not None:
            return

        if not self.check_wrapper():
            return

        server = self.server_var.get()
        mode = self.mode_var.get()

        cmd = [str(WRAPPER), f"--{server}", f"--{mode}"]

        self.clear_output()
        self.append("Comando:\n")
        self.append(" ".join(cmd) + "\n\n")

        self.start_process(cmd)

    def start_process(self, cmd):
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
            messagebox.showerror("Errore avvio", str(exc))
            return

        self.set_running(True)
        thread = threading.Thread(target=self.read_process_output, daemon=True)
        thread.start()

    def read_process_output(self):
        try:
            assert self.proc is not None
            assert self.proc.stdout is not None

            for line in self.proc.stdout:
                self.after(0, self.append, line)

            return_code = self.proc.wait()
            self.after(0, self.process_finished, return_code)
        except Exception as exc:
            self.after(0, self.process_failed, str(exc))

    def process_finished(self, return_code):
        self.append(f"\nProcesso terminato con codice: {return_code}\n")
        self.proc = None
        self.set_running(False)

    def process_failed(self, error):
        self.append(f"\nErrore processo: {error}\n")
        self.proc = None
        self.set_running(False)

    def stop_updater(self):
        if self.proc is None:
            return

        try:
            os.killpg(os.getpgid(self.proc.pid), signal.SIGTERM)
            self.append("\nRichiesto stop updater...\n")
        except Exception as exc:
            messagebox.showerror("Errore stop", str(exc))

    def on_close(self):
        if self.proc is not None:
            answer = messagebox.askyesno(
                "Updater attivo",
                "L'updater è ancora in esecuzione. Vuoi fermarlo e chiudere?",
            )
            if not answer:
                return
            self.stop_updater()

        self.destroy()


if __name__ == "__main__":
    app = EsoTtcUI()
    app.mainloop()
