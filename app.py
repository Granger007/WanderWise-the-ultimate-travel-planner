from flask import Flask, render_template, request, redirect, url_for, flash
import pymysql
from config import Config
from datetime import datetime

# =====================================================
# APP INITIALIZATION
# =====================================================
app = Flask(__name__)
app.config.from_object(Config)
app.secret_key = app.config['SECRET_KEY']

# =====================================================
# DATABASE CONNECTION
# =====================================================
def get_db():
    try:
        conn = pymysql.connect(
            host=app.config['DB_HOST'],
            user=app.config['DB_USER'],
            password=app.config['DB_PASS'],
            database=app.config['DB_NAME'],
            port=app.config['DB_PORT'],
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=False
        )
        conn.ping(reconnect=True)
        return conn
    except pymysql.MySQLError as e:
        app.logger.error(f"Database connection failed: {e}")
        flash("Database connection failed. Please try again later.", "danger")
        return None


# =====================================================
# COMPLEX QUERY ROUTES
# =====================================================
@app.route('/admin/query/<int:query_id>')
def admin_query(query_id):
    conn = get_db()
    if conn is None:
        return redirect(url_for("admin_dashboard"))

    with conn.cursor() as cur:
        if query_id == 1:
            cur.execute("""
                SELECT u.Name, u.Gmail, t.trip_id, t.total_cost
                FROM Users u
                JOIN TRIP t ON u.user_id = t.user_id
                WHERE t.total_cost > (SELECT AVG(total_cost) FROM TRIP);
            """)
            table_name = "Users Who Spent Above Average"

        elif query_id == 2:
            cur.execute("""
                SELECT 
                    h.hotel_name,
                    l.city_name AS city,
                    l.country_name AS country,
                    h.rating,
                    h.std_google_review,
                    RANK() OVER (PARTITION BY h.location_id ORDER BY h.rating DESC) AS rating_rank
                FROM HOTELS h
                JOIN LOCATION l ON h.location_id = l.location_id
                WHERE h.rating IS NOT NULL;
            """)
            table_name = "Hotel Rankings by Location"

        elif query_id == 3:
            cur.execute("""
                SELECT 
                    u.Name,
                    COUNT(DISTINCT t.trip_id) AS total_trips,
                    SUM(t.total_cost) AS total_spent,
                    AVG(t.total_cost) AS avg_trip_cost
                FROM Users u
                JOIN TRIP t ON u.user_id = t.user_id
                GROUP BY u.user_id, u.Name
                HAVING SUM(t.total_cost) > 1000;
            """)
            table_name = "Total Spending by User"

        elif query_id == 4:
            cur.execute("""
                WITH LocationActivityCount AS (
                    SELECT 
                        l.city_name,
                        l.country_name,
                        COUNT(a.activity_id) AS activity_count
                    FROM LOCATION l
                    LEFT JOIN ACTIVITY a ON l.location_id = a.location_id
                    GROUP BY l.location_id, l.city_name, l.country_name
                )
                SELECT * FROM LocationActivityCount
                WHERE activity_count = (SELECT MAX(activity_count) FROM LocationActivityCount);
            """)
            table_name = "Locations with Most Activities"

        elif query_id == 5:
            cur.execute("""
                SELECT 
                    t.trip_id,
                    u.Name,
                    f.flight_id,
                    f.flight_no,
                    f.airline_name,
                    f.base_price
                FROM TRIP t
                JOIN Users u ON t.user_id = u.user_id
                JOIN FLIGHT f ON t.flight_id = f.flight_id
                WHERE f.base_price > (
                    SELECT AVG(base_price)
                    FROM FLIGHT
                );
            """)
            table_name = "Flights Above Average Base Price"

        else:
            conn.close()
            return "Invalid query ID", 404

        rows = cur.fetchall()

    conn.close()
    return render_template("admin_table.html", table_name=table_name, rows=rows)


# =====================================================
# USER HOME PAGE
# =====================================================
@app.route("/", endpoint="user_home")
def home():
    return render_template("user.html")


# =====================================================
# 🔍 SEARCH FUNCTIONALITY
# =====================================================
@app.route("/search", methods=["GET"])
def search():
    query = request.args.get("query", "").strip()
    list_all = False
    if not query:
        # Show all results when query is empty
        list_all = True

    conn = get_db()
    if conn is None:
        return redirect(url_for("user_home"))

    with conn.cursor() as cur:
        def get_columns(table):
            cur.execute(f"SHOW COLUMNS FROM {table}")
            return {row['Field'] for row in cur.fetchall()}

        flight_cols = get_columns('FLIGHT')
        hotel_cols = get_columns('HOTELS')

        flight_price_col = 'base_price' if 'base_price' in flight_cols else ('price' if 'price' in flight_cols else None)
        flight_duration_col = 'flight_duration' if 'flight_duration' in flight_cols else ('duration' if 'duration' in flight_cols else None)

        select_parts = ['flight_id', 'flight_no', 'airline_name', 'dept_airport', 'arr_airport']
        if flight_price_col: select_parts.append(f"{flight_price_col} AS base_price")
        if flight_duration_col: select_parts.append(f"{flight_duration_col} AS flight_duration")
        select_sql = ", ".join(select_parts)

        cur.execute(f"""
            SELECT {select_sql}
            FROM FLIGHT
            {'' if list_all else 'WHERE flight_no LIKE %s OR airline_name LIKE %s OR dept_airport LIKE %s OR arr_airport LIKE %s'}
        """, (() if list_all else (f"%{query}%", f"%{query}%", f"%{query}%", f"%{query}%")))
        flights = cur.fetchall()

        hotel_select_parts = ['hotel_id', 'hotel_name', 'address', 'rating', 'amenities']
        if 'price_per_night' in hotel_cols:
            hotel_select_parts.append("price_per_night")
        hotel_select_sql = ", ".join(hotel_select_parts)

        cur.execute(f"""
            SELECT {hotel_select_sql}
            FROM HOTELS
            {'' if list_all else 'WHERE hotel_name LIKE %s OR address LIKE %s OR amenities LIKE %s'}
        """, (() if list_all else (f"%{query}%", f"%{query}%", f"%{query}%")))
        hotels = cur.fetchall()

        # Quick-add requires list of existing trips
        cur.execute("SELECT trip_id, user_id, start_date, end_date FROM TRIP ORDER BY trip_id DESC LIMIT 100")
        trips = cur.fetchall()

    conn.close()
    return render_template("search_results.html", query=query, flights=flights, hotels=hotels, trips=trips)


# =====================================================
# HOTEL BOOKING
# =====================================================
@app.route("/book/hotel/<int:hotel_id>", methods=["GET", "POST"])
def book_hotel(hotel_id):
    conn = get_db()
    if conn is None:
        return redirect(url_for("user_home"))

    with conn.cursor() as cur:
        cur.execute("SELECT * FROM HOTELS WHERE hotel_id = %s", (hotel_id,))
        hotel = cur.fetchone()
        cur.execute("SELECT trip_id, user_id FROM TRIP")
        trips = cur.fetchall()

    if request.method == "POST":
        trip_choice = request.form.get("trip_choice")

        try:
            with conn.cursor() as cur:
                if trip_choice == "existing":
                    trip_id = int(request.form["existing_trip"])
                else:
                    start_date = request.form.get("start_date")
                    end_date = request.form.get("end_date")
                    try:
                        sd = datetime.strptime(start_date, "%Y-%m-%d") if start_date else None
                        ed = datetime.strptime(end_date, "%Y-%m-%d") if end_date else None
                    except ValueError:
                        flash("Please enter valid trip start and end dates.", "warning")
                        return redirect(url_for("book_hotel", hotel_id=hotel_id))
                    if not sd or not ed:
                        flash("Trip start and end dates are required.", "warning")
                        return redirect(url_for("book_hotel", hotel_id=hotel_id))
                    if ed < sd:
                        flash("Trip end date must be on or after the start date.", "danger")
                        return redirect(url_for("book_hotel", hotel_id=hotel_id))
                    # Create user from provided details (insert or reuse by Gmail)
                    F_name = request.form.get("F_name")
                    L_name = request.form.get("L_name")
                    Gmail = request.form.get("Gmail")
                    Password = request.form.get("Password")
                    Phone_number = request.form.get("Phone_number")
                    DOB = request.form.get("DOB")
                    Passport_no = request.form.get("Passport_no")
                    if not (F_name and L_name and Gmail and Password):
                        flash("Please enter first name, last name, email and password to create a user.", "warning")
                        return redirect(url_for("book_hotel", hotel_id=hotel_id))
                    try:
                        cur.execute(
                            """
                            INSERT INTO USERS (F_name, L_name, DOB, Passport_no, Gmail, Password, Phone_number)
                            VALUES (%s,%s,%s,%s,%s,%s,%s)
                            """,
                            (F_name, L_name, DOB if DOB else None, Passport_no, Gmail, Password, Phone_number)
                        )
                        user_id = cur.lastrowid
                    except pymysql.err.IntegrityError:
                        # User exists by Gmail, fetch id
                        cur.execute("SELECT user_id FROM USERS WHERE Gmail = %s", (Gmail,))
                        row = cur.fetchone()
                        user_id = row["user_id"] if row else None
                        if not user_id:
                            flash("Could not create or find user.", "danger")
                            return redirect(url_for("book_hotel", hotel_id=hotel_id))
                    cur.execute("""
                        INSERT INTO TRIP (user_id, start_date, end_date)
                        VALUES (%s, %s, %s)
                    """, (user_id, start_date, end_date))
                    trip_id = cur.lastrowid

                room_type = request.form.get("room_type")
                check_in = request.form.get("check_in_date")
                check_out = request.form.get("check_out_date")
                guests = int(request.form.get("no_of_guests", 1))
                booking_ref = f"HTL{trip_id}{hotel_id}{int(datetime.now().timestamp())}"

                # Server-side validation to avoid DB constraint errors
                try:
                    ci_dt = datetime.strptime(check_in, "%Y-%m-%d") if check_in else None
                    co_dt = datetime.strptime(check_out, "%Y-%m-%d") if check_out else None
                except ValueError:
                    flash("Please enter valid check-in and check-out dates.", "warning")
                    return redirect(url_for("book_hotel", hotel_id=hotel_id))

                if not ci_dt or not co_dt:
                    flash("Check-in and check-out dates are required.", "warning")
                    return redirect(url_for("book_hotel", hotel_id=hotel_id))
                if co_dt <= ci_dt:
                    flash("Check-out date must be after check-in date.", "warning")
                    return redirect(url_for("book_hotel", hotel_id=hotel_id))

                try:
                    cur.execute("""
                        UPDATE TRIP
                        SET hotel_id = %s, room_type = %s, no_of_guests = %s,
                            check_in_date = %s, check_out_date = %s,
                            booking_ref = %s, status = 'Booked'
                        WHERE trip_id = %s
                    """, (hotel_id, room_type, guests, check_in, check_out, booking_ref, trip_id))
                except pymysql.err.OperationalError as e:
                    if getattr(e, 'args', None) and e.args[0] == 3819:
                        # MySQL check constraint violation (e.g., chk_hotel_dates)
                        conn.rollback()
                        flash("Check-out date must be after check-in date.", "danger")
                        return redirect(url_for("book_hotel", hotel_id=hotel_id))
                    raise

                # Recalculate total: flight + hotel(nights) + activities
                cur.execute(
                    """
                    SELECT 
                        COALESCE(f.base_price * COALESCE(t.no_of_guests,1),0) 
                      + COALESCE(
                          h.price_per_night * CASE 
                            WHEN t.check_in_date IS NOT NULL AND t.check_out_date IS NOT NULL 
                              THEN DATEDIFF(t.check_out_date, t.check_in_date) 
                            ELSE 0 
                          END,
                          0
                        )
                      + COALESCE((SELECT SUM(price) FROM ACTIVITY a WHERE a.trip_id = t.trip_id),0) AS total
                    FROM TRIP t
                    LEFT JOIN FLIGHT f ON t.flight_id = f.flight_id
                    LEFT JOIN HOTELS h ON t.hotel_id = h.hotel_id
                    WHERE t.trip_id = %s
                    """,
                    (trip_id,)
                )
                _row = cur.fetchone()
                total = (_row.get("total") if isinstance(_row, dict) else _row[0]) if _row else 0
                cur.execute("UPDATE TRIP SET total_cost = %s WHERE trip_id = %s", (total, trip_id))
                conn.commit()
                flash(f"Hotel '{hotel['hotel_name']}' booked successfully!", "success")
                return redirect(url_for("trip_summary", trip_id=trip_id))
        finally:
            conn.close()

    conn.close()
    return render_template("book_hotel.html", hotel=hotel, trips=trips)


# =====================================================
# FLIGHT BOOKING
# =====================================================
@app.route("/book/flight/<int:flight_id>", methods=["GET", "POST"])
def book_flight(flight_id):
    conn = get_db()
    if conn is None:
        return redirect(url_for("user_home"))

    with conn.cursor() as cur:
        cur.execute("SELECT flight_id, flight_no, airline_name, dept_airport, arr_airport, base_price AS price FROM FLIGHT WHERE flight_id = %s", (flight_id,))
        flight = cur.fetchone()
        cur.execute("SELECT trip_id, user_id, start_date, end_date FROM TRIP")
        trips = cur.fetchall()

    if request.method == "POST":
        trip_choice = request.form.get("trip_choice")
        try:
            with conn.cursor() as cur:
                if trip_choice == "existing":
                    trip_id = int(request.form["existing_trip"])
                else:
                    start_date = request.form.get("start_date")
                    end_date = request.form.get("end_date")
                    try:
                        sd = datetime.strptime(start_date, "%Y-%m-%d") if start_date else None
                        ed = datetime.strptime(end_date, "%Y-%m-%d") if end_date else None
                    except ValueError:
                        flash("Please enter valid trip start and end dates.", "warning")
                        return redirect(url_for("book_flight", flight_id=flight_id))
                    if not sd or not ed:
                        flash("Trip start and end dates are required.", "warning")
                        return redirect(url_for("book_flight", flight_id=flight_id))
                    if ed < sd:
                        flash("Trip end date must be on or after the start date.", "danger")
                        return redirect(url_for("book_flight", flight_id=flight_id))
                    # Create user from provided details (insert or reuse by Gmail)
                    F_name = request.form.get("F_name")
                    L_name = request.form.get("L_name")
                    Gmail = request.form.get("Gmail")
                    Password = request.form.get("Password")
                    Phone_number = request.form.get("Phone_number")
                    DOB = request.form.get("DOB")
                    Passport_no = request.form.get("Passport_no")
                    if not (F_name and L_name and Gmail and Password):
                        flash("Please enter first name, last name, email and password to create a user.", "warning")
                        return redirect(url_for("book_flight", flight_id=flight_id))
                    try:
                        cur.execute(
                            """
                            INSERT INTO USERS (F_name, L_name, DOB, Passport_no, Gmail, Password, Phone_number)
                            VALUES (%s,%s,%s,%s,%s,%s,%s)
                            """,
                            (F_name, L_name, DOB if DOB else None, Passport_no, Gmail, Password, Phone_number)
                        )
                        user_id = cur.lastrowid
                    except pymysql.err.IntegrityError:
                        cur.execute("SELECT user_id FROM USERS WHERE Gmail = %s", (Gmail,))
                        row = cur.fetchone()
                        user_id = row["user_id"] if row else None
                        if not user_id:
                            flash("Could not create or find user.", "danger")
                            return redirect(url_for("book_flight", flight_id=flight_id))
                    cur.execute(
                        """
                        INSERT INTO TRIP (user_id, start_date, end_date)
                        VALUES (%s, %s, %s)
                        """,
                        (user_id, start_date, end_date)
                    )
                    trip_id = cur.lastrowid

                booking_ref = f"FLT{trip_id}{flight_id}{int(datetime.now().timestamp())}"
                passengers = int(request.form.get("no_of_guests", 1))

                cur.execute(
                    """
                    UPDATE TRIP
                    SET flight_id = %s, no_of_guests = %s, booking_ref = %s, status = 'Booked'
                    WHERE trip_id = %s
                    """,
                    (flight_id, passengers, booking_ref, trip_id)
                )

                # Recalculate total: flight + hotel(nights) + activities
                cur.execute(
                    """
                    SELECT 
                        COALESCE(f.base_price * COALESCE(t.no_of_guests,1),0) 
                      + COALESCE(
                          h.price_per_night * CASE 
                            WHEN t.check_in_date IS NOT NULL AND t.check_out_date IS NOT NULL 
                              THEN DATEDIFF(t.check_out_date, t.check_in_date) 
                            ELSE 0 
                          END,
                          0
                        )
                      + COALESCE((SELECT SUM(price) FROM ACTIVITY a WHERE a.trip_id = t.trip_id),0) AS total
                    FROM TRIP t
                    LEFT JOIN FLIGHT f ON t.flight_id = f.flight_id
                    LEFT JOIN HOTELS h ON t.hotel_id = h.hotel_id
                    WHERE t.trip_id = %s
                    """,
                    (trip_id,)
                )
                _row = cur.fetchone()
                total = (_row.get("total") if isinstance(_row, dict) else _row[0]) if _row else 0
                cur.execute("UPDATE TRIP SET total_cost = %s WHERE trip_id = %s", (total, trip_id))
                conn.commit()
                flash(f"Flight '{flight['flight_no']}' booked successfully!", "success")
                return redirect(url_for("trip_summary", trip_id=trip_id))
        finally:
            conn.close()

    conn.close()
    return render_template("book_flight.html", flight=flight, trips=trips)


# =====================================================
# REMOVE COMPONENTS FROM TRIP (and recalc total)
# =====================================================
@app.post("/trip/<int:trip_id>/remove_flight")
def remove_trip_flight(trip_id):
    conn = get_db()
    if conn is None:
        return redirect(url_for("user_home"))
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE TRIP SET flight_id = NULL WHERE trip_id = %s", (trip_id,))
            cur.execute(
                """
                SELECT 
                    COALESCE(f.base_price * COALESCE(t.no_of_guests,1),0) 
                  + COALESCE(
                      h.price_per_night * CASE 
                        WHEN t.check_in_date IS NOT NULL AND t.check_out_date IS NOT NULL 
                          THEN DATEDIFF(t.check_out_date, t.check_in_date) 
                        ELSE 0 
                      END,
                      0
                    )
                  + COALESCE((SELECT SUM(price) FROM ACTIVITY a WHERE a.trip_id = t.trip_id),0) AS total
                FROM TRIP t
                LEFT JOIN FLIGHT f ON t.flight_id = f.flight_id
                LEFT JOIN HOTELS h ON t.hotel_id = h.hotel_id
                WHERE t.trip_id = %s
                """,
                (trip_id,)
            )
            _row = cur.fetchone()
            total = (_row.get("total") if isinstance(_row, dict) else _row[0]) if _row else 0
            cur.execute("UPDATE TRIP SET total_cost = %s WHERE trip_id = %s", (total, trip_id))
            conn.commit()
            flash("Flight removed from trip. Total updated.", "success")
    finally:
        conn.close()
    return redirect(url_for("trip_summary", trip_id=trip_id))


@app.post("/trip/<int:trip_id>/remove_hotel")
def remove_trip_hotel(trip_id):
    conn = get_db()
    if conn is None:
        return redirect(url_for("user_home"))
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE TRIP 
                SET hotel_id = NULL, room_type = NULL, no_of_guests = 1,
                    check_in_date = NULL, check_out_date = NULL
                WHERE trip_id = %s
                """,
                (trip_id,)
            )
            cur.execute(
                """
                SELECT 
                    COALESCE(f.base_price,0) 
                  + COALESCE(
                      h.price_per_night * CASE 
                        WHEN t.check_in_date IS NOT NULL AND t.check_out_date IS NOT NULL 
                          THEN DATEDIFF(t.check_out_date, t.check_in_date) 
                        ELSE 0 
                      END,
                      0
                    )
                  + COALESCE((SELECT SUM(price) FROM ACTIVITY a WHERE a.trip_id = t.trip_id),0) AS total
                FROM TRIP t
                LEFT JOIN FLIGHT f ON t.flight_id = f.flight_id
                LEFT JOIN HOTELS h ON t.hotel_id = h.hotel_id
                WHERE t.trip_id = %s
                """,
                (trip_id,)
            )
            _row = cur.fetchone()
            total = (_row.get("total") if isinstance(_row, dict) else _row[0]) if _row else 0
            cur.execute("UPDATE TRIP SET total_cost = %s WHERE trip_id = %s", (total, trip_id))
            conn.commit()
            flash("Hotel removed from trip. Total updated.", "success")
    finally:
        conn.close()
    return redirect(url_for("trip_summary", trip_id=trip_id))


# =====================================================
# TRIP SUMMARY
# =====================================================
@app.route("/trip/<int:trip_id>/summary")
def trip_summary(trip_id):
    conn = get_db()
    if conn is None:
        return redirect(url_for("user_home"))

    with conn.cursor() as cur:
        cur.execute("""
            SELECT 
                t.trip_id,
                u.Name AS user_name,
                t.start_date,
                t.end_date,
                DATEDIFF(t.end_date, t.start_date) AS duration_days,
                t.total_cost,
                -- hotel details
                h.hotel_name,
                h.address,
                t.room_type,
                t.no_of_guests,
                t.check_in_date,
                t.check_out_date,
                DATEDIFF(t.check_out_date, t.check_in_date) AS nights,
                h.price_per_night,
                -- flight details
                f.flight_id,
                f.flight_no,
                f.airline_name,
                f.base_price AS flight_base_price,
                t.booking_ref,
                t.status
            FROM TRIP t
            LEFT JOIN USERS u ON t.user_id = u.user_id
            LEFT JOIN HOTELS h ON t.hotel_id = h.hotel_id
            LEFT JOIN FLIGHT f ON t.flight_id = f.flight_id
            WHERE t.trip_id = %s
        """, (trip_id,))
        summary = cur.fetchall()

        cur.execute("""
            SELECT 
                TRIGGER_NAME,
                ACTION_TIMING,
                EVENT_MANIPULATION,
                EVENT_OBJECT_TABLE,
                ACTION_STATEMENT
            FROM information_schema.TRIGGERS
            WHERE TRIGGER_SCHEMA = DATABASE()
              AND EVENT_OBJECT_TABLE IN ('TRIP','ACTIVITY')
            ORDER BY EVENT_OBJECT_TABLE, TRIGGER_NAME
        """)
        triggers = cur.fetchall()

    conn.close()
    return render_template("trip_summary.html", summary=summary, trip_id=trip_id, triggers=triggers)


# =====================================================
# ADMIN DASHBOARD + TABLE MANAGEMENT
# =====================================================
@app.route('/admin_dashboard')
def admin_dashboard():
    valid_tables = ['Users', 'LOCATION', 'FLIGHT', 'HOTELS', 'TRIP', 'ACTIVITY']
    return render_template('admin_dashboard.html', tables=valid_tables)

@app.route('/admin')
def admin_redirect():
    return redirect(url_for('admin_dashboard'))

@app.route('/admin/triggers', endpoint='admin_triggers')
def admin_triggers():
    conn = get_db()
    if conn is None:
        return redirect(url_for('admin_dashboard'))

    with conn.cursor() as cur:
        cur.execute("""
            SELECT 
                TRIGGER_NAME,
                ACTION_TIMING,
                EVENT_MANIPULATION,
                EVENT_OBJECT_TABLE,
                ACTION_STATEMENT,
                DEFINER,
                CREATED
            FROM information_schema.TRIGGERS
            WHERE TRIGGER_SCHEMA = DATABASE()
            ORDER BY EVENT_OBJECT_TABLE, TRIGGER_NAME
        """)
        triggers = cur.fetchall()

    conn.close()
    return render_template('triggers.html', triggers=triggers)

@app.route('/admin/<string:table_name>', methods=["GET", "POST"], endpoint='admin_table')
def admin_table(table_name):
    allowed = {"USERS", "LOCATION", "FLIGHT", "HOTELS", "TRIP", "ACTIVITY"}
    tname = table_name.upper()
    if tname not in allowed:
        flash("Invalid table selected.", "danger")
        return redirect(url_for('admin_dashboard'))

    conn = get_db()
    if conn is None:
        return redirect(url_for('admin_dashboard'))

    pk_map = {"USERS":"user_id","LOCATION":"location_id","FLIGHT":"flight_id","HOTELS":"hotel_id","TRIP":"trip_id","ACTIVITY":"activity_id"}

    try:
        with conn.cursor() as cur:
            cur.execute(f"SHOW COLUMNS FROM {tname}")
            columns = [c['Field'] for c in cur.fetchall()]
            pk_col = pk_map.get(tname)

            if request.method == 'POST':
                action = request.form.get('action')
                if action == 'insert':
                    ins_fields = [c for c in columns if c != pk_col]
                    values = [request.form.get(c) for c in ins_fields]
                    placeholders = ", ".join(["%s"] * len(ins_fields))
                    cur.execute(f"INSERT INTO {tname} ({', '.join(ins_fields)}) VALUES ({placeholders})", values)
                    conn.commit()
                    flash(f"Inserted new record into {tname}.", "success")
                    return redirect(url_for('admin_table', table_name=tname))
                elif action == 'delete':
                    pk_val = request.form.get('pk')
                    cur.execute(f"DELETE FROM {tname} WHERE {pk_col} = %s", (pk_val,))
                    conn.commit()
                    flash(f"Deleted record with {pk_col} = {pk_val}.", "success")
                    return redirect(url_for('admin_table', table_name=tname))

            cur.execute(f"SELECT * FROM {tname} LIMIT 500")
            rows = cur.fetchall()

            cur.execute(
                """
                SELECT 
                    TRIGGER_NAME,
                    ACTION_TIMING,
                    EVENT_MANIPULATION,
                    EVENT_OBJECT_TABLE,
                    ACTION_STATEMENT
                FROM information_schema.TRIGGERS
                WHERE TRIGGER_SCHEMA = DATABASE() AND EVENT_OBJECT_TABLE = %s
                ORDER BY TRIGGER_NAME
                """,
                (tname,)
            )
            table_triggers = cur.fetchall()
    finally:
        conn.close()

    return render_template("admin_table.html", table_name=tname, rows=rows, fields=[c for c in columns if c != pk_col], triggers=table_triggers)


# =====================================================
# GLOBAL CONTEXT & ERRORS
# =====================================================
@app.context_processor
def inject_globals():
    return {"current_year": datetime.now().year}

@app.errorhandler(404)
def not_found_error(error):
    return render_template("errors.html", error_code=404, error_message=str(error)), 404

@app.errorhandler(500)
def internal_error(error):
    import traceback
    return render_template("errors.html", error_code=500, error_details=traceback.format_exc()), 500

# =====================================================
# MAIN
# =====================================================
if __name__ == "__main__":
    app.run(debug=True)
