# =====================================================
# Quick Commerce Dark Store - Synthetic Data Generator
# Colab me ek cell me paste karke Run karo.
# Output: 7 CSV files + dark_store_data.zip
# =====================================================
import numpy as np
import pandas as pd
import os, shutil

np.random.seed(42)
OUT = "dark_store_data"
os.makedirs(OUT, exist_ok=True)

START = pd.Timestamp("2026-01-01")
END = pd.Timestamp("2026-06-30")
DAYS = pd.date_range(START, END)

# ---------- 1. dark_stores ----------
stores_raw = [
    ("Hyderabad", "Madhapur"), ("Hyderabad", "Gachibowli"), ("Hyderabad", "Secunderabad"),
    ("Bengaluru", "Koramangala"), ("Bengaluru", "Whitefield"), ("Bengaluru", "Indiranagar"),
    ("Mumbai", "Andheri"), ("Mumbai", "Powai"), ("Mumbai", "Thane"),
    ("Delhi", "Dwarka"), ("Delhi", "Saket"), ("Delhi", "Rohini"),
]
dark_stores = pd.DataFrame({
    "store_id": range(1, len(stores_raw) + 1),
    "city": [c for c, a in stores_raw],
    "area": [a for c, a in stores_raw],
    "store_size_sqft": np.random.choice([1500, 2000, 2500, 3000], len(stores_raw)),
    "monthly_rent": np.random.choice([150000, 200000, 250000, 300000], len(stores_raw)),
})
# Har store ki apni quality (kuch store weak honge -> insights milenge)
store_stockout_bias = np.random.uniform(0.02, 0.15, len(stores_raw))   # stock-out chance
store_speed = np.random.uniform(0.85, 1.25, len(stores_raw))           # delivery speed factor

# ---------- 2. products ----------
cats = {
    "Dairy": [("Milk 500ml", 30), ("Curd 400g", 45), ("Paneer 200g", 90), ("Butter 100g", 58),
              ("Cheese Slices", 140), ("Eggs 6pc", 60), ("Lassi 200ml", 25)],
    "Snacks": [("Lays Chips", 20), ("Kurkure", 20), ("Bhujia 200g", 55), ("Popcorn", 40),
               ("Nachos", 99), ("Namkeen Mix", 65), ("Peanuts 200g", 50), ("Cream Biscuits", 30)],
    "Fruits & Veg": [("Banana 1dz", 60), ("Apple 1kg", 180), ("Tomato 1kg", 40), ("Onion 1kg", 45),
                     ("Potato 1kg", 35), ("Spinach", 25), ("Coriander", 15), ("Lemon 250g", 30)],
    "Beverages": [("Coke 750ml", 40), ("Pepsi 750ml", 40), ("Frooti", 20), ("Red Bull", 125),
                  ("Packaged Water 1L", 20), ("Cold Coffee", 60), ("Tea 250g", 130)],
    "Staples": [("Atta 5kg", 250), ("Rice 5kg", 420), ("Toor Dal 1kg", 160), ("Oil 1L", 150),
                ("Sugar 1kg", 50), ("Salt 1kg", 25), ("Maggi 4pk", 56)],
    "Personal Care": [("Shampoo", 190), ("Soap 3pk", 120), ("Toothpaste", 95), ("Face Wash", 160),
                      ("Deodorant", 220), ("Sanitary Pads", 85)],
    "Household": [("Detergent 1kg", 130), ("Dishwash Gel", 99), ("Floor Cleaner", 150),
                  ("Garbage Bags", 80), ("Tissue Roll", 70), ("Toilet Cleaner", 110)],
    "Frozen & Ice Cream": [("Vanilla Ice Cream", 100), ("Chocolate Ice Cream", 120), ("Frozen Peas", 90),
                           ("Chicken Nuggets", 220), ("French Fries", 150), ("Kulfi", 40)],
}
rows = []
pid = 1
for cat, items in cats.items():
    for name, mrp in items:
        cost = round(mrp * np.random.uniform(0.70, 0.88), 2)
        shelf = {"Dairy": 7, "Fruits & Veg": 5, "Frozen & Ice Cream": 90}.get(cat, 180)
        rows.append((pid, name, cat, mrp, cost, shelf))
        pid += 1
products = pd.DataFrame(rows, columns=["product_id", "product_name", "category", "mrp", "cost_price", "shelf_life_days"])

# ---------- 3. customers ----------
N_CUST = 20000
signup = pd.to_datetime("2025-10-01") + pd.to_timedelta(np.random.randint(0, 273, N_CUST), unit="D")
cust_city = np.random.choice(["Hyderabad", "Bengaluru", "Mumbai", "Delhi"], N_CUST, p=[0.28, 0.30, 0.22, 0.20])
customers = pd.DataFrame({
    "customer_id": range(1, N_CUST + 1),
    "city": cust_city,
    "signup_date": signup.date,
    "segment": np.random.choice(["Student", "Working Professional", "Family"], N_CUST, p=[0.25, 0.45, 0.30]),
})

# ---------- 4. delivery_partners ----------
N_RIDERS = 90
delivery_partners = pd.DataFrame({
    "partner_id": range(1, N_RIDERS + 1),
    "store_id": np.random.choice(dark_stores.store_id, N_RIDERS),
    "shift": np.random.choice(["Morning", "Evening", "Night"], N_RIDERS, p=[0.35, 0.45, 0.20]),
    "rating": np.round(np.random.uniform(3.4, 5.0, N_RIDERS), 1),
    "joined_date": (pd.to_datetime("2025-01-01") + pd.to_timedelta(np.random.randint(0, 500, N_RIDERS), unit="D")).date,
})

# ---------- 5. orders ----------
N_ORDERS = 60000
# Rain wale din (lagbhag 20% din, Jun-me zyada)
rain = {d: (np.random.rand() < (0.45 if d.month in (6,) else 0.12)) for d in DAYS}

# customer weights: kuch customers zyada order karte hain (repeat behaviour)
w = np.random.lognormal(0, 0.9, N_CUST)
w = w / w.sum()
cust_ids = np.random.choice(customers.customer_id, N_ORDERS, p=w)
cust_signup = pd.to_datetime(customers.set_index("customer_id").loc[cust_ids, "signup_date"].values)
cust_city_o = customers.set_index("customer_id").loc[cust_ids, "city"].values

# order date: signup ke baad, END tak
lo = np.maximum(cust_signup.values, START.to_datetime64())
span = (END.to_datetime64() - lo).astype("timedelta64[D]").astype(int) + 1
order_day = pd.to_datetime(lo) + pd.to_timedelta((np.random.rand(N_ORDERS) * span).astype(int), unit="D")

# hour: shaam 6-9 peak, subah 8-10 chhota peak
hour_p = np.array([1,1,0.5,0.3,0.3,0.5,1,2,4,4,3,3,3.5,3,3,3,4,6,10,10,8,6,3,2], dtype=float)
hour_p /= hour_p.sum()
hours = np.random.choice(24, N_ORDERS, p=hour_p)
minutes = np.random.randint(0, 60, N_ORDERS)
order_time = order_day + pd.to_timedelta(hours, unit="h") + pd.to_timedelta(minutes, unit="m")

# store: customer ke city ke stores me se
store_by_city = dark_stores.groupby("city")["store_id"].apply(list).to_dict()
store_ids = np.array([np.random.choice(store_by_city[c]) for c in cust_city_o])

# delivery time (minutes)
base = np.random.normal(7.5, 2.0, N_ORDERS)
speed = store_speed[store_ids - 1]
is_rain = np.array([rain[d.normalize()] for d in order_time])
peak = ((hours >= 18) & (hours <= 21)).astype(float)
delivery_min = base * speed + is_rain * np.random.uniform(3, 7, N_ORDERS) + peak * np.random.uniform(1, 3, N_ORDERS)
delivery_min = np.clip(delivery_min, 4, 45).round(1)

status = np.random.choice(["Delivered", "Cancelled"], N_ORDERS, p=[0.965, 0.035])
partner_pool = delivery_partners.groupby("store_id")["partner_id"].apply(list).to_dict()
partners = np.array([np.random.choice(partner_pool.get(s, delivery_partners.partner_id.tolist())) for s in store_ids])

orders = pd.DataFrame({
    "order_id": range(1, N_ORDERS + 1),
    "customer_id": cust_ids,
    "store_id": store_ids,
    "partner_id": partners,
    "order_time": order_time,
    "delivery_time_min": np.where(status == "Cancelled", np.nan, delivery_min),
    "delivery_fee": np.random.choice([0, 15, 25, 35], N_ORDERS, p=[0.35, 0.25, 0.25, 0.15]),
    "payment_mode": np.random.choice(["UPI", "Card", "COD", "Wallet"], N_ORDERS, p=[0.60, 0.15, 0.15, 0.10]),
    "is_rainy_day": is_rain.astype(int),
    "status": status,
}).sort_values("order_time").reset_index(drop=True)
orders["order_id"] = range(1, N_ORDERS + 1)

# ---------- 6. order_items ----------
# Category preference: weekend + snacks/ice cream, subah dairy
cat_w = {"Dairy": 1.6, "Snacks": 1.4, "Fruits & Veg": 1.5, "Beverages": 1.0,
         "Staples": 0.8, "Personal Care": 0.4, "Household": 0.5, "Frozen & Ice Cream": 0.7}
item_rows = []
prod_cat = products.set_index("product_id")["category"].to_dict()
base_p = np.array([cat_w[prod_cat[p]] for p in products.product_id])
n_items = np.random.choice([1, 2, 3, 4, 5, 6], N_ORDERS, p=[0.18, 0.28, 0.24, 0.16, 0.09, 0.05])
for oid, ot, n in zip(orders.order_id.values, orders.order_time.values, n_items):
    ot = pd.Timestamp(ot)
    p = base_p.copy()
    cats_arr = products.category.values
    if ot.weekday() >= 5:
        p[(cats_arr == "Snacks") | (cats_arr == "Frozen & Ice Cream") | (cats_arr == "Beverages")] *= 1.6
    if ot.hour < 11:
        p[cats_arr == "Dairy"] *= 2.0
    p = p / p.sum()
    chosen = np.random.choice(products.product_id.values, size=n, replace=False, p=p)
    for pr in chosen:
        item_rows.append((oid, int(pr), int(np.random.choice([1, 2, 3], p=[0.7, 0.22, 0.08]))))
order_items = pd.DataFrame(item_rows, columns=["order_id", "product_id", "quantity"])
order_items.insert(0, "order_item_id", range(1, len(order_items) + 1))
order_items = order_items.merge(products[["product_id", "mrp"]], on="product_id")
order_items["selling_price"] = (order_items["mrp"] * np.random.choice([1.0, 0.95, 0.90], len(order_items), p=[0.6, 0.25, 0.15])).round(2)
order_items = order_items.drop(columns="mrp").sort_values("order_item_id").reset_index(drop=True)

# ---------- 7. inventory_daily ----------
inv = pd.MultiIndex.from_product([DAYS, dark_stores.store_id, products.product_id],
                                 names=["date", "store_id", "product_id"]).to_frame(index=False)
inv = inv.merge(products[["product_id", "category"]], on="product_id")
cat_risk = {"Dairy": 1.8, "Snacks": 1.2, "Fruits & Veg": 2.0, "Beverages": 1.0,
            "Staples": 0.5, "Personal Care": 0.4, "Household": 0.4, "Frozen & Ice Cream": 1.4}
prob = store_stockout_bias[inv.store_id.values - 1] * inv.category.map(cat_risk).values
prob = prob * np.where(inv.date.dt.weekday >= 5, 1.3, 1.0)   # weekend pe zyada
inv["stockout_flag"] = (np.random.rand(len(inv)) < prob).astype(int)
inv["opening_stock"] = np.random.randint(20, 120, len(inv))
inv["closing_stock"] = np.where(inv.stockout_flag == 1, 0, np.random.randint(1, 60, len(inv)))
inv["units_wasted"] = np.where(inv.category.isin(["Dairy", "Fruits & Veg"]),
                               np.random.poisson(1.2, len(inv)), 0)
inv = inv.drop(columns="category")
inv["date"] = inv["date"].dt.date
inv.insert(0, "inventory_id", range(1, len(inv) + 1))

# ---------- Save ----------
tables = {
    "dark_stores": dark_stores, "products": products, "customers": customers,
    "delivery_partners": delivery_partners, "orders": orders,
    "order_items": order_items, "inventory_daily": inv,
}
for name, df in tables.items():
    df.to_csv(f"{OUT}/{name}.csv", index=False)
    print(f"{name:18s} -> {len(df):>8,} rows")

shutil.make_archive(OUT, "zip", OUT)
print("\nDone! 'dark_store_data.zip' ban gaya.")

# Colab me ho to zip seedha download ho jayega
try:
    from google.colab import files
    files.download("dark_store_data.zip")
except Exception:
    pass
