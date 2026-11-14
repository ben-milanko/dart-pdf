import sys
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.pdfbase.pdfmetrics import stringWidth
import json

W, H = letter
c = canvas.Canvas(sys.argv[1], pagesize=letter)
c.setTitle("Design Services Agreement")
ink = HexColor("#1d2330"); grey = HexColor("#5b6472"); rule = HexColor("#d5dae1")
geo = {}
L = 72; R = W - 72

# brand mark
c.setFillColor(HexColor("#0f8fd6")); c.roundRect(L, H-86, 22, 22, 5, fill=1, stroke=0)
c.setFillColor(ink); c.setFont("Helvetica-Bold", 11); c.drawString(L+30, H-79, "Northwind Studio")
c.setFont("Helvetica", 8.5); c.setFillColor(grey); c.drawRightString(R, H-79, "Agreement No. NW-2026-118")
c.setStrokeColor(rule); c.setLineWidth(0.8); c.line(L, H-98, R, H-98)

c.setFillColor(ink); c.setFont("Helvetica-Bold", 20); c.drawString(L, H-134, "Design Services Agreement")
c.setFont("Helvetica", 10); c.setFillColor(grey)
c.drawString(L, H-152, "Between Northwind Studio (\"Studio\") and the client named below (\"Client\").")

def field_row(y, label, name, x, w):
    c.setFont("Helvetica", 8); c.setFillColor(grey); c.drawString(x, y+18, label.upper())
    c.acroForm.textfield(name=name, x=x, y=y, width=w, height=16, borderWidth=0,
        fillColor=None, borderColor=None, fontSize=10.5, fontName="Helvetica", textColor=ink)
    c.setStrokeColor(rule); c.line(x, y, x+w, y)
    geo[name] = [x, y, x+w, y+16]

y = H-196
field_row(y, "Client name", "client", L, 250)
field_row(y, "Start date", "start", L+272, 90)
field_row(y, "Project fee", "fee", L+382, R-(L+382))

def para(y, heading, lines, size=9.6, lead=14):
    c.setFont("Helvetica-Bold", 11); c.setFillColor(ink); c.drawString(L, y, heading)
    y -= 18; c.setFont("Helvetica", size); c.setFillColor(HexColor("#2f3644"))
    pos = []
    for ln in lines:
        c.drawString(L, y, ln); pos.append((y, ln)); y -= lead
    return y - 10, pos

y = H-246
y, _ = para(y, "1. Scope of work", [
  "The Studio will design a brand identity for the Client: a logo, a colour palette,",
  "a type system, and a one-page style guide, delivered as editable source files.",
])
y, p2 = para(y, "2. Fees and payment", [
  "The Client will pay the project fee in two equal instalments: 50% on signing and",
  "50% on final delivery. Invoices are due within 14 days of the invoice date.",
  "Late payments may incur a fee of 1.5% per month on the outstanding balance.",
])
# highlight geometry: second line of section 2, the phrase "Invoices are due within 14 days of the invoice date."
yy, ln = p2[1]
pre = "50% on final delivery. "
x0 = L + stringWidth(pre, "Helvetica", 9.6); x1 = L + stringWidth(ln, "Helvetica", 9.6)
geo["hl"] = [x0-1, yy-3, x1+1, yy+9.5]
geo["hl_note"] = [x1+6, yy+14]
y, p4 = para(y, "3. Ownership", [
  "On full payment, the Client owns the final deliverables outright. The Studio may",
  "show the work in its portfolio unless the Client asks otherwise in writing.",
])
yy, ln = p4[0]
geo["ul"] = [L-1, yy-3, L+stringWidth("On full payment, the Client owns the final deliverables outright.", "Helvetica", 9.6)+1, yy+9.5]
c.setFont("Helvetica", 9.6); c.setFillColor(HexColor("#2f3644"))
c.acroForm.checkbox(name="agree", x=L, y=y-4, size=11, borderColor=HexColor("#8a93a0"), fillColor=None, buttonStyle="check", checked=False, borderWidth=0.8)
geo["agree"] = [L, y-4, L+11, y+7]
c.drawString(L+18, y-2, "I have read and agree to the terms above.")

# signature block
sy = y - 78
for i, (who, nm) in enumerate([("Client signature", "client_sig"), ("Studio signature", "studio_sig")]):
    x = L + i*(R-L)/2 + (0 if i == 0 else 12)
    w = (R-L)/2 - 12
    c.setStrokeColor(HexColor("#8a93a0")); c.line(x, sy, x+w, sy)
    c.setFont("Helvetica", 8); c.setFillColor(grey); c.drawString(x, sy-12, who.upper())
    geo[nm] = [x, sy, x+w, sy+44]
c.setFont("Helvetica-Oblique", 7.5); c.setFillColor(grey)
c.drawString(L, 60, "Northwind Studio · 14 Harbour Lane · Page 1 of 1")
c.showPage(); c.save()
json.dump(geo, open(sys.argv[2], "w"), indent=1)
