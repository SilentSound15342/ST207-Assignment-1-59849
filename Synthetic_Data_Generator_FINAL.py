import random, math
from datetime import datetime, timedelta

random.seed(42)
TODAY = datetime(2026, 10, 31)          # 'current date' of the scenario
END   = datetime(2026, 10, 28, 20, 0)   # last possible order timestamp
OUT   = "Q4_Ecommerce_Data_FINAL.sql"

def q(v):
    """SQL literal"""
    if v is None: return "NULL"
    if isinstance(v, (int, float)): return repr(round(v, 2)) if isinstance(v, float) else str(v)
    return "'" + str(v).replace("'", "''") + "'"
def ts(d): return d.strftime("%Y-%m-%d %H:%M:%S")

# ------------------------------------------------------------------ categories
CATS = [  # (id, name, parent)
 (1,"Electronics",None),(2,"Fashion",None),(3,"Home & Kitchen",None),(4,"Sports & Outdoors",None),
 (5,"Phones & Tablets",1),(6,"Audio",1),(7,"Computing",1),
 (8,"Men's Clothing",2),(9,"Women's Clothing",2),(10,"Footwear",2),
 (11,"Kitchen Appliances",3),(12,"Bedding",3),
 (13,"Fitness",4),(14,"Camping",4),
 (15,"Headphones",6),(16,"Speakers",6),(17,"Laptops",7),(18,"Computer Accessories",7),
 (19,"Toys & Games",None),            # deliberately EMPTY category (edge case)
]
cat_parent = {c[0]: c[2] for c in CATS}
def root(c):
    while cat_parent[c] is not None: c = cat_parent[c]
    return c

CL = ["S","M","L","XL"]; W = ["8","10","12","14"]; SH = ["6","7","8","9","10","11"]
# (name, brand, description, category_id, base_price, sizes, colours, size_price_step)
PRODUCTS = [
 ("Nova X5 Smartphone","Nova","6.1-inch OLED smartphone with dual camera",5,449,["128GB","256GB"],["Midnight","Silver"],80),
 ("Nova Tab 10 Tablet","Nova","10-inch tablet for work and play",5,299,["64GB","128GB"],["Graphite"],60),
 ("Pixelon Lite Smartphone","Pixelon","Budget 6.5-inch smartphone",5,229,["64GB","128GB"],["Black","Blue"],40),
 ("ShieldCase Phone Case","ShieldGuard","Drop-protection case",5,14.99,None,["Black","Clear","Navy"],0),
 ("Aurora ANC Headphones","Aurora","Over-ear active noise-cancelling headphones",15,199,None,["Black","White","Navy"],0),
 ("Beat Buds Wireless Earbuds","Beatly","True wireless earbuds, 24h battery",15,79,None,["Black","White"],0),
 ("StudioPro Over-Ear Headphones","Sonique","Wired studio monitoring headphones",15,149,None,["Black"],0),
 ("SportFit Earphones","Beatly","Sweat-proof neckband earphones",15,39,None,["Black","Red"],0),
 ("Boombox Mini Speaker","Sonique","Portable Bluetooth speaker",16,49,None,["Black","Teal"],0),
 ("Boombox Max Speaker","Sonique","Party Bluetooth speaker, 20h battery",16,129,None,["Black"],0),
 ("SmartHub Voice Speaker","Hubly","Voice-assistant smart speaker",16,69,None,["White","Charcoal"],0),
 ("Zenith Air 13 Laptop","Zenith","Ultralight 13-inch laptop",17,849,["256GB","512GB"],["Silver"],150),
 ("Zenith Pro 15 Laptop","Zenith","15-inch performance laptop",17,1299,["512GB","1TB"],["Space Grey"],200),
 ("Ember Student Laptop","Ember","Affordable laptop for students",17,429,["128GB","256GB"],["Grey"],70),
 ("Glide Wireless Mouse","Logix","Ergonomic wireless mouse",18,24.99,None,["Black","White","Grey"],0),
 ("KeyForge Mechanical Keyboard","KeyForge","Hot-swappable mechanical keyboard",18,79,None,["Black","White"],0),
 ("Volt 65W GaN Charger","Voltix","Compact USB-C fast charger",18,34.99,None,None,0),
 ("USB-C Hub 7-in-1","Voltix","HDMI, USB-A, SD and PD pass-through",18,44.99,None,["Grey"],0),
 ("ViewMax 27in Monitor","ViewMax","27-inch QHD IPS monitor",18,189,None,None,0),
 ("Classic Cotton T-Shirt","Northline","100% cotton crew-neck tee",8,14.99,CL,["White","Black","Navy"],0),
 ("Slim Fit Chinos","Northline","Stretch cotton chinos",8,39.99,["30","32","34","36"],["Khaki","Navy"],0),
 ("Fleece Hoodie","Northline","Brushed fleece pullover hoodie",8,44.99,CL,["Grey","Black"],0),
 ("Waterproof Jacket","Stormcraft","Lightweight waterproof shell",8,89,CL,["Green","Black"],0),
 ("Linen Summer Dress","Marlow","Breathable linen midi dress",9,49.99,W,["Blue","Cream"],0),
 ("High-Rise Jeans","Marlow","Stretch denim high-rise jeans",9,54.99,W,["Denim"],0),
 ("Merino Wool Jumper","Marlow","Soft merino crew-neck jumper",9,64.99,CL[:3],["Burgundy","Grey"],0),
 ("Yoga Leggings","Flexa","High-waist performance leggings",9,29.99,CL[:3],["Black","Plum"],0),
 ("Road Runner Trainers","Stridex","Cushioned running trainers",10,79.99,SH,["Black/Grey","Blue"],0),
 ("Leather Chelsea Boots","Hartley","Full-grain leather boots",10,119,SH,["Brown","Black"],0),
 ("Everyday Canvas Sneakers","Stridex","Classic low-top sneakers",10,34.99,SH,["White","Black"],0),
 ("Trail Runner Limited Edition","Stridex","Limited run trail shoe",10,109.99,["7","8","9","10"],["Orange"],0),
 ("Brewmaster Coffee Machine","Brewmaster","Programmable drip coffee machine",11,89,None,["Black","Silver"],0),
 ("AirCrisp Air Fryer 5L","CrispCo","5-litre digital air fryer",11,99.99,None,["Black"],0),
 ("BlendPro 1000W Blender","BlendPro","High-speed countertop blender",11,59.99,None,["Black","Red"],0),
 ("QuickBoil Kettle","Brewmaster","1.7L fast-boil kettle",11,29.99,None,["White","Steel"],0),
 ("CloudSoft Duvet","Slumbr","10.5 tog microfibre duvet",12,49.99,["Single","Double","King"],None,8),
 ("Egyptian Cotton Sheet Set","Slumbr","400-thread-count sheet set",12,39.99,["Double","King"],["White","Grey"],6),
 ("Memory Foam Pillow","Slumbr","Contour memory foam pillow",12,24.99,None,None,0),
 ("Pro Yoga Mat","Flexa","6mm non-slip yoga mat",13,22.99,None,["Purple","Blue","Black"],0),
 ("Adjustable Dumbbell Set","IronCore","Adjustable dumbbell pair",13,129,["10kg","20kg"],None,70),
 ("Resistance Bands Set","IronCore","Set of 5 resistance bands",13,14.99,None,None,0),
 ("Smart Fitness Watch","Pulsar","GPS fitness tracker watch",13,119,None,["Black","Silver"],0),
 ("Foam Roller","IronCore","High-density foam roller",13,17.99,None,["Black"],0),
 ("2-Person Tent","Wildpeak","3-season 2-person tent",14,109,None,["Green","Orange"],0),
 ("Sleeping Bag -5C","Wildpeak","Mummy sleeping bag rated to -5C",14,59.99,None,["Green","Navy"],0),
 ("Headtorch 400 Lumen","Wildpeak","Rechargeable LED headtorch",14,19.99,None,["Black"],0),
]
# co-purchased pairs (drive basket-analysis structure)
BUNDLES = [("Zenith Air 13 Laptop","Glide Wireless Mouse"),("Zenith Pro 15 Laptop","USB-C Hub 7-in-1"),
 ("Nova X5 Smartphone","ShieldCase Phone Case"),("Nova X5 Smartphone","Volt 65W GaN Charger"),
 ("Aurora ANC Headphones","Nova X5 Smartphone"),("Road Runner Trainers","SportFit Earphones"),
 ("Pro Yoga Mat","Resistance Bands Set"),("CloudSoft Duvet","Egyptian Cotton Sheet Set"),
 ("2-Person Tent","Sleeping Bag -5C"),("Brewmaster Coffee Machine","QuickBoil Kettle"),
 ("Classic Cotton T-Shirt","Slim Fit Chinos"),("KeyForge Mechanical Keyboard","Glide Wireless Mouse"),
 ("ViewMax 27in Monitor","USB-C Hub 7-in-1"),("Smart Fitness Watch","Road Runner Trainers"),
 ("Ember Student Laptop","Glide Wireless Mouse")]

# ------------------------------------------------------------------ products / variants
products, variants = [], []
pid_by_name, pop, quality = {}, {}, {}
vid = 0
for i, (name, brand, desc, cat, base, sizes, colours, step) in enumerate(PRODUCTS, start=1):
    products.append((i, name, desc, brand, cat)); pid_by_name[name] = i
    pop[i] = math.exp(random.gauss(0, 0.8))               # popularity weight
    quality[i] = min(4.9, max(2.6, random.gauss(4.1, 0.55)))
    for si, s in enumerate(sizes or [None]):
        for c in (colours or [None]):
            vid += 1
            tag = "".join(ch for ch in brand.upper() if ch.isalnum())[:3]
            sku = f"{tag}-{i:03d}-{vid:04d}"
            variants.append(dict(id=vid, sku=sku, price=round(base + step*si, 2), size=s, colour=c, pid=i, stock=0))
variants_by_pid = {}
for v in variants: variants_by_pid.setdefault(v["pid"], []).append(v)
partners = {}
for a, b in BUNDLES:
    partners.setdefault(pid_by_name[a], []).append(pid_by_name[b])
    partners.setdefault(pid_by_name[b], []).append(pid_by_name[a])
prod_cat = {p[0]: p[4] for p in products}

# ------------------------------------------------------------------ customers & addresses
FIRST = ["Olivia","Amelia","Isla","Ava","Mia","Grace","Sophie","Freya","Ella","Priya","Aisha","Chloe","Emily","Zara","Hannah",
         "Oliver","George","Noah","Arthur","Leo","Oscar","Harry","Jack","Charlie","Ravi","Omar","Liam","Ethan","Kai","Daniel",
         "Mateo","Lucas","Ines","Sofia","Anna","Marta","Tomas","Jonas","Elena","Yusuf"]
LAST = ["Smith","Jones","Taylor","Brown","Williams","Wilson","Davies","Evans","Thomas","Roberts","Johnson","Walker","Wright",
        "Robinson","Thompson","White","Hughes","Edwards","Green","Hall","Patel","Khan","Singh","Ahmed","Murphy","Kelly",
        "O'Brien","Ryan","Garcia","Novak","Kowalski","Silva","Rossi","Martin","Clarke","Baker","Turner","Hill","Cooper","Ward"]
CITIES = [("London","UK",8),("Manchester","UK",4),("Birmingham","UK",3),("Leeds","UK",2),("Glasgow","UK",2),("Bristol","UK",2),
          ("Edinburgh","UK",2),("Liverpool","UK",2),("Cardiff","UK",1),("Dublin","Ireland",1),("Paris","France",1),("Berlin","Germany",1)]
CNAME = {"UK":"United Kingdom"}
STREETS = ["High Street","Station Road","Church Lane","Victoria Road","Park Avenue","Mill Lane","King Street","Queen's Road",
           "Green Lane","Manor Road","Oak Drive","Albert Street"]
PCODE = ["E","N","SW","SE","W","M","B","LS","G","BS","EH","L","CF"]

NCUST = 260
customers, addresses, cust_info = [], [], {}
emails = set(); aid = 0
for cid in range(1, NCUST + 1):
    r = random.random()
    seg = "heavy" if r < .08 else "regular" if r < .43 else "occasional" if r < .78 else "never"
    if seg == "never":   reg = TODAY - timedelta(days=random.randint(3, 700))
    elif seg == "heavy": reg = datetime(2024,1,1) + timedelta(days=random.randint(0, 300))
    else:                reg = datetime(2024,1,1) + timedelta(days=random.randint(0, 800))
    reg = reg.replace(hour=random.randint(7,22), minute=random.randint(0,59), second=random.randint(0,59))
    f, l = random.choice(FIRST), random.choice(LAST)
    base = f"{f}.{l}".lower().replace("'", "")
    em, k = f"{base}@example.com", 1
    while em in emails: k += 1; em = f"{base}{k}@example.com"
    emails.add(em)
    customers.append((cid, f, l, em, ts(reg)))
    n_addr = random.choices([1,2,3],[.6,.3,.1])[0]
    city, country, _ = random.choices(CITIES, [c[2] for c in CITIES])[0]
    my = []
    for j in range(n_addr):
        aid += 1
        if j: city, country, _ = random.choices(CITIES, [c[2] for c in CITIES])[0]
        pc = f"{random.choice(PCODE)}{random.randint(1,20)} {random.randint(1,9)}{random.choice('ABDEFGHJLNPQRSTUWXYZ')}{random.choice('ABDEFGHJLNPQRSTUWXYZ')}"
        active = 0 if (j == 0 and n_addr > 1 and random.random() < .35) else 1   # old address deactivated
        addresses.append((aid, f"{random.randint(1,220)} {random.choice(STREETS)}", city, pc, CNAME.get(country, country), active, cid))
        my.append((aid, active, country))
    favs = random.sample([1,2,3,4], k=random.choice([1,2]))
    cust_info[cid] = dict(seg=seg, reg=reg, addrs=my, favs=favs)
addr_of = {a[0]: a for a in addresses}

# ------------------------------------------------------------------ orders
def season_w(d):  # relative order intensity by month + mild growth
    m = {1:.9,2:.8,3:.85,4:.85,5:.9,6:.9,7:.95,8:.85,9:.9,10:1.0,11:1.6,12:2.0}[d.month]
    return m * (1 + 0.25 * (d - datetime(2024,1,1)).days / 1000)
def rand_date(lo, hi):
    while True:
        d = lo + timedelta(seconds=random.randint(0, int((hi - lo).total_seconds())))
        if random.random() < season_w(d) / 2.6:
            return d

def pick_product(favs):
    ids = list(pop)
    w = [pop[i] * (3 if root(prod_cat[i]) in favs else 1) for i in ids]
    return random.choices(ids, w)[0]

orders_raw = []
for cid, ci in cust_info.items():
    if ci["seg"] == "never": continue
    n = {"heavy": random.randint(8,20), "regular": random.randint(3,7), "occasional": random.randint(1,2)}[ci["seg"]]
    lo = ci["reg"] + timedelta(hours=2)
    if lo >= END: continue
    for _ in range(n):
        orders_raw.append((rand_date(lo, END), cid))
orders_raw.sort()

orders, items, payments, cardpays = [], [], [], []
oi_id = pay_id = 0
txn = 0
for oid, (odt, cid) in enumerate(orders_raw, start=1):
    ci = cust_info[cid]
    # ---- lines
    pset = [pick_product(ci["favs"])]
    if random.random() < .38 and partners.get(pset[0]): pset.append(random.choice(partners[pset[0]]))
    if random.random() < .35: pset.append(pick_product(ci["favs"]))
    if random.random() < .10: pset.append(pick_product(ci["favs"]))
    pset = list(dict.fromkeys(pset))
    total = 0.0; lines = []
    for p in pset:
        v = random.choice(variants_by_pid[p])
        qty = random.choices([1,2,3],[.8,.15,.05])[0]
        price = v["price"]
        if odt < datetime(2026,1,1): price = round(price * 0.96, 2)           # earlier price level
        if (odt.month == 11 and odt.day >= 20) or (odt.month == 12 and odt.day <= 3):
            if random.random() < .45: price = round(price * 0.85, 2)           # Black-Friday style discount
        oi_id += 1
        items.append((oi_id, qty, price, v["id"], oid)); lines.append((v, qty)); total += qty * price
    # ---- address (inactive addresses only for early orders)
    act = [a for a in ci["addrs"] if a[1] == 1]; allad = ci["addrs"]
    early = odt < ci["reg"] + (END - ci["reg"]) / 2
    pool = allad if early and random.random() < .5 else act
    ship = random.choice(pool)
    bill = ship if random.random() < .8 else random.choice(allad)
    fee = 0.0 if (total >= 50 and ship[2] == "UK") else (3.99 if ship[2] == "UK" else 9.99)
    total = round(total + fee, 2)
    # ---- status by age
    age = (TODAY - odt).days
    if age <= 1:   st = random.choices(["Pending","Paid"],[.55,.45])[0]
    elif age <= 4: st = random.choices(["Pending","Paid","Shipped","Cancelled"],[.10,.25,.60,.05])[0]
    else:          st = random.choices(["Delivered","Cancelled","Shipped"],[.90,.08,.02])[0]
    shipped = None
    if st in ("Shipped","Delivered"):
        shipped = min(odt + timedelta(days=random.randint(1,3), hours=random.randint(0,6)), TODAY)
    orders.append((oid, ts(odt), st, fee, ts(shipped) if shipped else None, cid, ship[0], bill[0], total, shipped))
    # ---- payments
    def add_pay(amount, method, status, at):
        global pay_id, txn
        pay_id += 1; txn += 1
        payments.append((pay_id, round(amount,2), method, status, ts(at), f"TXN-{txn:07d}", oid))
        if method == "Card":
            cardpays.append((pay_id, random.choices(["Visa","Mastercard","Amex"],[.55,.35,.10])[0], f"{random.randint(0,9999):04d}"))
        return pay_id
    meth = random.choices(["Card","PayPal","Bank Transfer"],[.68,.24,.08])[0]
    t0 = odt + timedelta(minutes=random.randint(1,6))
    if st == "Pending":
        r = random.random()
        if r < .50: pass                                         # nothing attempted yet
        elif r < .80: add_pay(total, meth, "Failed", t0)
        else:         add_pay(total, meth, "Pending", t0)
    elif st == "Cancelled":
        if random.random() < .45: add_pay(total, meth, "Failed", t0)
        else:                      add_pay(total, meth, "Refunded", t0)    # paid, then cancelled -> refunded
    else:  # Paid / Shipped / Delivered -> completed payment(s) covering the total
        if random.random() < .12:                                          # failed first attempt, then retry
            add_pay(total, meth, "Failed", t0); t0 += timedelta(minutes=random.randint(2,15))
            meth = random.choices(["Card","PayPal"],[.6,.4])[0]
        if random.random() < .04 and total > 40:                           # split payment
            a1 = round(total * .4, 2)
            add_pay(a1, "PayPal", "Completed", t0); add_pay(round(total - a1, 2), "Card", "Completed", t0 + timedelta(minutes=2))
        else:
            add_pay(total, meth, "Completed", t0)

# ------------------------------------------------------------------ carts / cart items
carts, citems = [], []
cart_id = ci_id = 0
order_lines_by_cust = {}
for o in orders:
    order_lines_by_cust.setdefault(o[5], []).append(o)
oi_by_order = {}
for it in items: oi_by_order.setdefault(it[4], []).append(it)
for cid, ci in cust_info.items():
    if random.random() > .40: continue
    cart_id += 1
    cdate = max(ci["reg"] + timedelta(hours=1), TODAY - timedelta(days=random.randint(1, 120)))
    carts.append((cart_id, ts(cdate), cid))
    used = set()
    for _ in range(random.randint(1, 4)):
        d = cdate + timedelta(days=random.random() * (TODAY - cdate).days)
        v = random.choice(variants_by_pid[pick_product(ci["favs"])])
        if random.random() < .25 and cid in order_lines_by_cust:           # item the customer later bought anyway
            ords = [o for o in order_lines_by_cust[cid] if datetime.strptime(o[1], "%Y-%m-%d %H:%M:%S") > cdate + timedelta(days=2)]
            if ords:
                o = random.choice(ords); it = random.choice(oi_by_order[o[0]])
                v = next(x for x in variants if x["id"] == it[3])
                d = datetime.strptime(o[1], "%Y-%m-%d %H:%M:%S") - timedelta(days=random.randint(1, 3))
                d = max(d, cdate)
        if v["id"] in used: continue
        used.add(v["id"]); ci_id += 1
        citems.append((ci_id, random.choices([1,2],[.85,.15])[0], ts(d), cart_id, v["id"]))

# ------------------------------------------------------------------ reviews (verified purchasers)
reviews = []; rv = 0; seen = set()
# a few products deliberately have NO reviews (edge case for rating queries / LEFT JOINs)
no_review = {pid_by_name[n] for n in ("Foam Roller","Headtorch 400 Lumen","Trail Runner Limited Edition","Boombox Max Speaker")}
for o in orders:
    if o[2] != "Delivered": continue
    cid = o[5]; dd = datetime.strptime(o[4], "%Y-%m-%d %H:%M:%S")
    for it in oi_by_order[o[0]]:
        p = next(x for x in variants if x["id"] == it[3])["pid"]
        if p in no_review or (cid, p) in seen or random.random() > .33: continue
        seen.add((cid, p))
        rd = dd + timedelta(days=random.randint(3, 30), hours=random.randint(0, 20))
        if rd > END: continue
        rating = int(min(5, max(1, round(random.gauss(quality[p], 0.9)))))
        com = None
        if random.random() < .6:
            com = random.choice({5:["Excellent, exactly as described.","Love it - fast delivery too.","Great quality for the price."],
                                 4:["Very good, would buy again.","Good value, minor niggles only."],
                                 3:["Does the job but nothing special.","Average - sizing was a bit off."],
                                 2:["Not as good as expected.","Disappointing build quality."],
                                 1:["Stopped working after a week.","Poor quality, returning it."]}[rating])
        rv += 1; reviews.append((rv, rating, ts(rd), com, cid, p))

# ------------------------------------------------------------------ stock (after sales, so history is consistent)
for v in variants:
    v["stock"] = random.choice([0,1,2,3,4,5]) if random.random() < .08 else random.randint(8, 160)
# fixed demo variants for the trigger demonstrations (Question 6)
for v in variants:
    if v["pid"] == pid_by_name["Trail Runner Limited Edition"]:
        v["stock"] = 3 if v["size"] == "9" else v["stock"]
    if v["pid"] == pid_by_name["Aurora ANC Headphones"] and v["colour"] == "Navy":
        v["stock"] = 0
    if v["pid"] == pid_by_name["Glide Wireless Mouse"] and v["colour"] == "Black":
        v["stock"] = 40

# ------------------------------------------------------------------ write SQL
def block(table, cols, rows, chunk=100):
    out = [f"-- {table}: {len(rows)} rows"]
    for i in range(0, len(rows), chunk):
        part = rows[i:i+chunk]
        out.append(f"INSERT INTO {table} ({', '.join(cols)}) VALUES")
        out.append(",\n".join("  (" + ", ".join(q(x) for x in r) + ")" for r in part) + ";")
    return "\n".join(out) + "\n"

with open(OUT, "w", encoding="utf-8") as f:
    f.write("PRAGMA foreign_keys = ON;\n\n")
    f.write(block("Customer", ["customer_id","first_name","last_name","email","registered_at"], customers))
    f.write(block("Address", ["address_id","street","city","postcode","country","is_active","customer_id"], addresses))
    f.write(block("Category", ["category_id","name","parent_category_id"], CATS))
    f.write(block("Product", ["product_id","name","description","brand","category_id"], products))
    f.write(block("ProductVariant", ["variant_id","sku","unit_price","stock_quantity","size","colour","product_id"],
                  [(v["id"],v["sku"],v["price"],v["stock"],v["size"],v["colour"],v["pid"]) for v in variants]))
    f.write(block("Cart", ["cart_id","created_at","customer_id"], carts))
    f.write(block("CartItem", ["cart_item_id","quantity","created_at","cart_id","variant_id"], citems))
    f.write(block("CustomerOrder", ["order_id","order_date","status","shipping_fee","shipped_at","customer_id","shipping_address_id","billing_address_id"],
                  [o[:8] for o in orders]))
    f.write(block("OrderItem", ["order_item_id","quantity","unit_price_at_purchase","variant_id","order_id"], items))
    f.write(block("Payment", ["payment_id","amount","method","status","attempted_at","transaction_ref","order_id"], payments))
    f.write(block("CardPayment", ["payment_id","card_network","card_last4"], cardpays))
    f.write(block("Review", ["review_id","rating","review_date","comment","customer_id","product_id"], reviews))

print("customers", len(customers), "addresses", len(addresses), "products", len(products), "variants", len(variants))
print("carts", len(carts), "cartitems", len(citems), "orders", len(orders), "items", len(items),
      "payments", len(payments), "cardpayments", len(cardpays), "reviews", len(reviews))
for v in variants:
    if v["pid"] in (pid_by_name["Trail Runner Limited Edition"], pid_by_name["Aurora ANC Headphones"], pid_by_name["Glide Wireless Mouse"]):
        print(v["sku"], v["pid"], v["size"], v["colour"], v["stock"])
