#!/usr/bin/env python3
import subprocess
import os
import sys
import re

def build():
    with open("HANDBUCH.md", "r", encoding="utf-8") as f:
        text = f.read()

    # Ensure blank line before tables and lists when fed to pandoc
    lines = text.splitlines()
    processed = []
    for i, line in enumerate(lines):
        if i > 0 and lines[i-1].strip() != "":
            # Before table start
            if line.strip().startswith("|") and not lines[i-1].strip().startswith("|"):
                processed.append("")
            # Before list start
            elif re.match(r"^(\s*[-*+]|\s*\d+\.)\s+", line) and not re.match(r"^(\s*[-*+]|\s*\d+\.)\s+", lines[i-1]):
                processed.append("")
        processed.append(line)

    new_md = "\n".join(processed)

    # 1. Generate typst body from preprocessed markdown
    res = subprocess.run(["pandoc", "-t", "typst"], input=new_md, capture_output=True, text=True, check=True)
    body = res.stdout

    # Remove the duplicate top-level H1 title from body since our banner displays it prominently
    body_lines = body.splitlines()
    filtered_body_lines = []
    skip_next_label = False
    pagebreak_prefixes = (
        "== 3. Betriebssystem",
        "== 4. Bereitstellung",
        "=== 4.3 Ausführen der 1-Klick-Erst-Einrichtung",
        "== 5. Microsoft Office",
        "== 7. Laufender Betrieb",
    )
    for bl in body_lines:
        if bl.startswith("= Caritas Laptops: Installations- und Betriebshandbuch"):
            skip_next_label = True
            continue
        if skip_next_label and bl.startswith("<caritas-laptops"):
            skip_next_label = False
            continue
        skip_next_label = False
        if any(bl.startswith(p) for p in pagebreak_prefixes):
            filtered_body_lines.append("#pagebreak()")
        filtered_body_lines.append(bl)
    body = "\n".join(filtered_body_lines)

    # 1. Add zero-width space in long email address for clean word breaking
    body = body.replace("julia.bretterklieber@caritas-steiermark.at", "julia.bretterklieber@\u200bcaritas-steiermark.at")

    # 2. Optimize column widths for tables
    body = re.sub(
        r"#table\(\s*columns:\s*\(\s*25%,\s*25%,\s*25%,\s*25%\s*\)",
        r"#table(\n    columns: (18%, 34%, 22%, 26%)",
        body
    )
    body = re.sub(
        r"#table\(\s*columns:\s*\(\s*20%,\s*20%,\s*20%,\s*20%,\s*20%\s*\)",
        r"#table(\n    columns: (27%, 22%, 21%, 15%, 15%)",
        body
    )
    body = re.sub(
        r"#table\(\s*columns:\s*\(\s*50%,\s*50%\s*\)",
        r"#table(\n    columns: (30%, 70%)",
        body
    )

    # Typst template with Caritas corporate identity and professional document styling
    typst_template = r"""
#set page(
  paper: "a4",
  margin: (top: 2.2cm, bottom: 2.2cm, left: 1.8cm, right: 1.8cm),
  header: context {
    if here().page() > 1 [
      #grid(
        columns: (1fr, auto),
        align: (left, right),
        text(size: 8pt, fill: rgb("#64748B"), weight: "medium")[Caritas Steiermark · IT-Administration],
        text(size: 8pt, fill: rgb("#C41230"), weight: "bold")[Caritas Laptop Management-Suite v1.0.9]
      )
      #v(-2pt)
      #line(length: 100%, stroke: 0.5pt + rgb("#E2E8F0"))
    ]
  },
  footer: context [
    #line(length: 100%, stroke: 0.5pt + rgb("#E2E8F0"))
    #v(-2pt)
    #grid(
      columns: (1fr, auto),
      align: (left, right),
      text(size: 8pt, fill: rgb("#94A3B8"))[Installations- und Betriebshandbuch · Vertraulich · Interner Dienstgebrauch],
      text(size: 8pt, fill: rgb("#64748B"), weight: "bold")[Seite #counter(page).display() von #counter(page).final().at(0)]
    )
  ]
)

#set text(
  font: ("Inter", "Liberation Sans", "DejaVu Sans"),
  size: 9.5pt,
  fill: rgb("#1E293B"),
  lang: "de",
  region: "AT",
  hyphenate: auto
)

#set par(
  justify: true,
  leading: 0.65em
)

#show link: set text(fill: rgb("#C41230"))

#show raw: set text(font: ("Liberation Mono", "DejaVu Sans Mono"), size: 8pt)
#show raw.where(block: false): it => highlight(
  fill: rgb("#F1F5F9"),
  radius: 2pt
)[#text(font: ("Liberation Mono", "DejaVu Sans Mono"), size: 8pt)[#it]]

#show raw.where(block: true): it => block(
  fill: rgb("#F8FAFC"),
  inset: 8pt,
  radius: 4pt,
  stroke: 0.5pt + rgb("#E2E8F0"),
  width: 100%
)[#it]

#show heading.where(level: 1): it => {
  v(14pt)
  text(fill: rgb("#C41230"), weight: "bold", size: 13.5pt)[#it.body]
  v(2pt)
  line(length: 100%, stroke: 1.5pt + rgb("#C41230"))
  v(6pt)
}

#show heading.where(level: 2): it => {
  v(12pt)
  text(fill: rgb("#1E293B"), weight: "bold", size: 11pt)[#it.body]
  v(4pt)
}

#show heading.where(level: 3): it => {
  v(10pt)
  text(fill: rgb("#475569"), weight: "bold", size: 10pt)[#it.body]
  v(3pt)
}

#show table: set text(size: 8pt)
#show table.cell.where(y: 0): set text(weight: "bold", fill: white)
#set table(
  stroke: 0.5pt + rgb("#CBD5E1"),
  fill: (col, row) => if row == 0 { rgb("#C41230") } else if calc.even(row) { rgb("#F8FAFC") } else { white },
  inset: (x: 5pt, y: 5pt)
)

#let horizontalrule = line(length: 100%, stroke: 0.5pt + rgb("#E2E8F0"))

// Title Banner
#align(center)[
  #block(
    fill: rgb("#C41230"),
    inset: (x: 20pt, y: 14pt),
    radius: 4pt,
    width: 100%
  )[
    #text(fill: white, size: 18pt, weight: "bold")[Caritas Laptops]\
    #v(3pt)
    #text(fill: rgb("#FEE2E2"), size: 12pt, weight: "medium")[Installations- und Betriebshandbuch]\
    #v(2pt)
    #text(fill: rgb("#FECACA"), size: 8.5pt)[Version 1.0.9 · Caritas Steiermark · Stand: September 2026]
  ]
]

#v(8pt)
"""

    full_typst = typst_template + "\n" + body

    os.makedirs(".scratch", exist_ok=True)
    with open(".scratch/handbuch.typ", "w", encoding="utf-8") as f:
        f.write(full_typst)

    print("Compiling .scratch/handbuch.typ -> HANDBUCH.pdf...")
    res = subprocess.run(["typst", "compile", ".scratch/handbuch.typ", "HANDBUCH.pdf"], capture_output=True, text=True)
    if res.returncode != 0:
        print("Typst compile error:\n", res.stderr)
        sys.exit(res.returncode)
    
    size = os.path.getsize("HANDBUCH.pdf")
    print(f"Successfully generated HANDBUCH.pdf! ({round(size / 1024, 1)} KB)")

if __name__ == "__main__":
    build()
