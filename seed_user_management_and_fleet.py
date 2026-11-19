import json
import urllib.request
import urllib.parse
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

FIRESTORE_BASE = "https://firestore.googleapis.com/v1/projects/takemytrash/databases/(default)/documents"

# --- Curated Authentic Indian Boy and Girl Names ---
BOY_NAMES = [
    "Aarav", "Advik", "Akash", "Alok", "Aman", "Amit", "Ankit", "Arjun", "Ashish", "Bharat",
    "Chetan", "Deepak", "Dev", "Devesh", "Dinesh", "Dhruv", "Eeshan", "Farhan", "Gautam", "Gaurav",
    "Harish", "Harsh", "Inder", "Ishan", "Jatin", "Kabir", "Kapil", "Karthik", "Kunal", "Lokesh",
    "Madhav", "Manish", "Manoj", "Mayank", "Mohit", "Nakul", "Naveen", "Nikhil", "Nitin", "Om",
    "Pankaj", "Parth", "Prakash", "Pranav", "Raghav", "Rahul", "Rajesh", "Rakesh", "Ramesh", "Reyansh",
    "Rishi", "Rohan", "Rohit", "Sachin", "Sanjay", "Sandeep", "Shaurya", "Shivam", "Siddharth", "Soham",
    "Sumit", "Sunil", "Suresh", "Tarun", "Tushar", "Utkarsh", "Varun", "Ved", "Vijay", "Vikas",
    "Vikram", "Vishal", "Yash", "Yuvraj", "Vivaan", "Vihaan", "Ayush", "Abhay", "Animesh", "Bhavesh",
    "Chirag", "Darshan", "Hitesh", "Jagdish", "Jitendra", "Kalyan", "Lalit", "Mahesh", "Nitesh", "Paresh",
    "Piyush", "Ritesh", "Satish", "Tejas", "Umesh", "Vipul", "Yogesh", "Abhinav", "Abhishek", "Brijesh",
    "Chandan", "Divyansh", "Girish", "Hemant", "Kamal", "Kailash", "Manan", "Neeraj", "Prashant", "Ravindra"
]

GIRL_NAMES = [
    "Aadhya", "Ananya", "Anita", "Anjali", "Anvi", "Archana", "Avani", "Bhavana", "Chetna", "Deepa",
    "Deepali", "Divya", "Fatima", "Garima", "Geetha", "Hemlata", "Indu", "Ira", "Juhi", "Jyoti",
    "Kashvi", "Kavya", "Kiara", "Kiran", "Komal", "Lakshmi", "Leela", "Madhu", "Manisha", "Meenakshi",
    "Meera", "Myra", "Namrata", "Navya", "Neha", "Nisha", "Ojasvi", "Pallavi", "Pari", "Payal",
    "Pooja", "Poonam", "Preeti", "Prisha", "Radhika", "Rashmi", "Rekha", "Riddhi", "Ritu", "Riya",
    "Rupal", "Saanvi", "Sakshi", "Samaira", "Sanvi", "Sara", "Shanaya", "Shilpa", "Shreya", "Shweta",
    "Simran", "Siya", "Sneha", "Sonal", "Srishti", "Sunita", "Swati", "Swetha", "Tanvi", "Trisha",
    "Urmila", "Vandana", "Vidya", "Yamini", "Zara", "Amrita", "Bipasha", "Charu", "Damini", "Ekta",
    "Gayatri", "Harini", "Ishita", "Jahnvi", "Karishma", "Lavanya", "Malini", "Nandini", "Pooja", "Raveena",
    "Shruti", "Sonali", "Sujata", "Sushma", "Tulsi", "Vaishali", "Varsha", "Babita", "Chaya", "Durga",
    "Esha", "Gauri", "Hema", "Jaya", "Kalyani", "Kavita", "Lata", "Manju", "Padma", "Sarita"
]

LAST_NAMES = [
    "Kumar", "Sharma", "Patel", "Singh", "Rao", "Gowda", "Reddy", "Verma", "Nair", "Gupta",
    "Das", "Joshi", "Mehta", "Kulkarni", "Yadav", "Mishra", "Prasad", "Bhat", "Hegde", "Naik"
]

def make_firestore_request(url, method="PATCH", data=None, max_retries=3):
    encoded_data = json.dumps(data).encode("utf-8") if data else None
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(
                url,
                data=encoded_data,
                headers={"Content-Type": "application/json"} if data else {},
                method=method
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                return json.loads(resp.read().decode("utf-8")) if method != "DELETE" else True
        except Exception as e:
            if attempt == max_retries - 1:
                print(f"❌ Failed {method} on {url}: {e}")
                return None
            time.sleep(1)

def seed():
    print("======================================================================")
    print("  🚀 SEEDING USERS & VEHICLES INTO FIRESTORE (takemytrash)")
    print("======================================================================")

    # 1. Load authentic GIS data
    with open("AIQ_authority app/assets/gis/bengaluru_wards_zones.json", "r", encoding="utf-8") as f:
        gis = json.load(f)

    wards = sorted(gis.get("wards", []), key=lambda w: w.get("wardNo", 0))
    zones = sorted(gis.get("zones", []), key=lambda z: z.get("id", ""))

    print(f"Loaded {len(zones)} Zones and {len(wards)} Wards from official GIS asset.")

    tasks = []

    # 2. Zone Officers (8 zones)
    # user_name.zoney@gmail.com where y is 1..8
    zone_officer_records = []
    for idx, z in enumerate(zones, 1):
        is_boy = (idx % 2 != 0)
        first_name = BOY_NAMES[(idx - 1) % len(BOY_NAMES)] if is_boy else GIRL_NAMES[(idx - 1) % len(GIRL_NAMES)]
        username = first_name.lower().strip()
        email = f"{username}.zone{idx}@gmail.com"
        zone_name = z.get("name")
        doc_id = f"zone_officer_{z.get('id')}"

        doc_payload = {
            "fields": {
                "name": {"stringValue": first_name},
                "email": {"stringValue": email},
                "password": {"stringValue": "123456"},
                "phone": {"stringValue": "1234567890"},
                "role": {"stringValue": "Zone Officer"},
                "zone": {"stringValue": zone_name},
                "ward": {"stringValue": "All Wards"},
                "status": {"stringValue": "Active"}
            }
        }
        url = f"{FIRESTORE_BASE}/authority_users/{doc_id}"
        tasks.append((url, "PATCH", doc_payload, f"Zone Officer: {first_name} ({email})"))
        zone_officer_records.append({
            "name": first_name,
            "role": "Zone Officer",
            "zone": zone_name,
            "ward": "All Wards",
            "email": email,
            "phone": "1234567890",
            "password": "123456"
        })

    # 3. Ward Officers (198 wards)
    # user_name.wardxx@gmail.com
    ward_officer_records = []
    # Start offset for names to ensure variety
    for w in wards:
        ward_no = w.get("wardNo")
        is_boy = (ward_no % 2 != 0)
        # Offset to not repeat the zone officer names
        name_idx = ward_no + 8
        first_name = BOY_NAMES[name_idx % len(BOY_NAMES)] if is_boy else GIRL_NAMES[name_idx % len(GIRL_NAMES)]
        username = first_name.lower().strip()
        
        # xx format: ward01, ward02 ... ward99, ward100 ... ward198
        xx_str = f"{ward_no:02d}" if ward_no < 100 else f"{ward_no}"
        email = f"{username}.ward{xx_str}@gmail.com"
        ward_name = w.get("name")
        zone_name = w.get("zone")
        doc_id = f"ward_officer_{ward_no}"

        doc_payload = {
            "fields": {
                "name": {"stringValue": first_name},
                "email": {"stringValue": email},
                "password": {"stringValue": "123456"},
                "phone": {"stringValue": "1234567890"},
                "role": {"stringValue": "Ward Officer"},
                "zone": {"stringValue": zone_name},
                "ward": {"stringValue": ward_name},
                "status": {"stringValue": "Active"}
            }
        }
        url = f"{FIRESTORE_BASE}/authority_users/{doc_id}"
        tasks.append((url, "PATCH", doc_payload, f"Ward Officer: {first_name} ({email})"))
        ward_officer_records.append({
            "wardNo": ward_no,
            "name": first_name,
            "role": "Ward Officer",
            "zone": zone_name,
            "ward": ward_name,
            "email": email,
            "phone": "1234567890",
            "password": "123456"
        })

    # 4. Fleet Vehicles (2 per ward = 396 vehicles)
    # KA 01 AA 0001 upwards
    vehicle_records = []
    veh_counter = 1
    for w in wards:
        ward_no = w.get("wardNo")
        ward_name = w.get("name")
        zone_name = w.get("zone")

        for v_num in range(1, 3):
            veh_str = f"KA 01 AA {veh_counter:04d}"
            is_boy = (veh_counter % 2 != 0)
            f_name = BOY_NAMES[(veh_counter * 3) % len(BOY_NAMES)] if is_boy else GIRL_NAMES[(veh_counter * 3) % len(GIRL_NAMES)]
            l_name = LAST_NAMES[veh_counter % len(LAST_NAMES)]
            driver_full_name = f"{f_name} {l_name}"

            doc_payload = {
                "fields": {
                    "vehicleNumber": {"stringValue": veh_str},
                    "driverName": {"stringValue": driver_full_name},
                    "phoneNumber": {"stringValue": "1234567890"},
                    "password": {"stringValue": "123456"},
                    "zone": {"stringValue": zone_name},
                    "assignedWard": {"stringValue": ward_name},
                    "ward": {"stringValue": ward_name},
                    "isActive": {"booleanValue": True}
                }
            }
            encoded_id = urllib.parse.quote(veh_str)
            url = f"{FIRESTORE_BASE}/vehicles/{encoded_id}"
            tasks.append((url, "PATCH", doc_payload, f"Vehicle: {veh_str} -> {driver_full_name}"))
            vehicle_records.append({
                "vehicleNumber": veh_str,
                "driverName": driver_full_name,
                "phoneNumber": "1234567890",
                "password": "123456",
                "zone": zone_name,
                "assignedWard": ward_name
            })
            veh_counter += 1

    print(f"Total write operations queued: {len(tasks)} (8 Zone Officers + 198 Ward Officers + 396 Vehicles)")

    # 5. Execute writes concurrently
    completed = 0
    errors = 0
    with ThreadPoolExecutor(max_workers=15) as executor:
        futures = {executor.submit(make_firestore_request, url, method, data): desc for url, method, data, desc in tasks}
        for future in as_completed(futures):
            res = future.result()
            if res:
                completed += 1
            else:
                errors += 1
            if completed % 50 == 0 or completed == len(tasks):
                print(f"Progress: {completed}/{len(tasks)} items committed to Firestore (Errors: {errors})")

    # 6. Delete old mock test vehicles if they exist
    print("\nCleaning up legacy lowercase test vehicles...")
    for old_veh in ["ka 01 aa 0001", "ka 01 aa 0002"]:
        enc = urllib.parse.quote(old_veh)
        make_firestore_request(f"{FIRESTORE_BASE}/vehicles/{enc}", method="DELETE")
        print(f"Cleaned legacy test vehicle: {old_veh}")

    # 7. Verification Summary
    print("\n======================================================================")
    print("  ✅ SEEDING COMPLETE SUMMARY")
    print("======================================================================")
    print(f"Total Zone Officers Created: {len(zone_officer_records)}")
    for z in zone_officer_records:
        print(f"  • {z['zone']}: {z['name']} | Email: {z['email']} | Pass: {z['password']}")

    print(f"\nTotal Ward Officers Created: {len(ward_officer_records)}")
    print(f"Sample First 5 Ward Officers:")
    for w in ward_officer_records[:5]:
        print(f"  • Ward {w['wardNo']} ({w['zone']}): {w['name']} | Email: {w['email']}")
    print(f"Sample Last 5 Ward Officers:")
    for w in ward_officer_records[-5:]:
        print(f"  • Ward {w['wardNo']} ({w['zone']}): {w['name']} | Email: {w['email']}")

    print(f"\nTotal Vehicles Created: {len(vehicle_records)} (starting from KA 01 AA 0001 to KA 01 AA {veh_counter-1:04d})")
    print(f"Sample Vehicles:")
    for v in vehicle_records[:4]:
        print(f"  • {v['vehicleNumber']} | Driver: {v['driverName']} | Ward: {v['assignedWard']}")
    for v in vehicle_records[-2:]:
        print(f"  • {v['vehicleNumber']} | Driver: {v['driverName']} | Ward: {v['assignedWard']}")

    # Save details locally for quick reference
    with open("seeded_credentials.json", "w", encoding="utf-8") as f:
        json.dump({
            "zone_officers": zone_officer_records,
            "ward_officers": ward_officer_records,
            "vehicles": vehicle_records
        }, f, indent=2)
    print("\nFull credentials dump saved to 'seeded_credentials.json'")

if __name__ == "__main__":
    seed()

